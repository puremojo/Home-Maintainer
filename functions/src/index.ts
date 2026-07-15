import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { initializeApp } from "firebase-admin/app";
import { GoogleGenerativeAI } from "@google/generative-ai";

initializeApp();

// Token limits must match UserSubscriptionData.tierLimits in iOS
const TIER_LIMITS: Record<string, number> = {
  free: 100_000,
  standard: 1_000_000,
  pro: 5_000_000,
};

const SYSTEM_PROMPT = `You are hAIndyman, a helpful AI assistant specialized in home maintenance. You help users with:
- Creating and managing maintenance tasks
- Appliance care and troubleshooting
- Finding local service providers
- Managing repair projects
- General home improvement advice
- Analyzing images of appliances, repairs, or maintenance issues

When users send images, analyze them and provide helpful advice about what you see.
When users ask you to create tasks, add appliances, or make changes, use the available tools to actually perform these actions.

Be concise, practical, and friendly.`;

const TOOLS = [
  {
    functionDeclarations: [
      {
        name: "create_maintenance_task",
        description: "Create a new maintenance task in the user's home maintenance app",
        parameters: {
          type: "OBJECT",
          properties: {
            name: { type: "STRING", description: "The name of the task (e.g., 'Change HVAC Filter')" },
            description: { type: "STRING", description: "Description of what needs to be done" },
            frequency: {
              type: "STRING",
              enum: ["daily", "weekly", "biweekly", "monthly", "quarterly", "biannually", "annually"],
              description: "How often the task should be performed",
            },
          },
          required: ["name", "description", "frequency"],
        },
      },
      {
        name: "create_appliance",
        description: "Add a new appliance to track in the user's home",
        parameters: {
          type: "OBJECT",
          properties: {
            name: { type: "STRING", description: "Name of the appliance (e.g., 'Kitchen Refrigerator')" },
            type: {
              type: "STRING",
              enum: ["refrigerator", "dishwasher", "washer", "dryer", "oven", "microwave", "hvac", "waterHeater", "garbageDisposal", "other"],
              description: "Type of appliance",
            },
            manufacturer: { type: "STRING", description: "Manufacturer name" },
          },
          required: ["name", "type"],
        },
      },
      {
        name: "search_local_providers",
        description: "Search for local service providers near the user (plumbers, electricians, etc.)",
        parameters: {
          type: "OBJECT",
          properties: {
            category: {
              type: "STRING",
              enum: ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter", "painter", "landscaper", "handyman", "appliance"],
              description: "Type of service provider to search for",
            },
          },
          required: ["category"],
        },
      },
      {
        name: "save_search_result",
        description: "Save a specific numbered result from the most recent search_local_providers call to the user's saved providers. Use this (not add_service_provider) whenever the user asks to add a result by number from a local search.",
        parameters: {
          type: "OBJECT",
          properties: {
            resultNumber: {
              type: "NUMBER",
              description: "The result number to save (1, 2, 3… as listed in the search output)",
            },
          },
          required: ["resultNumber"],
        },
      },
      {
        name: "add_service_provider",
        description: "Add a service provider by name/details when NOT coming from a local search result. Include ALL known details — phone, address, website, and rating.",
        parameters: {
          type: "OBJECT",
          properties: {
            name: { type: "STRING", description: "Business name" },
            category: {
              type: "STRING",
              enum: ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter", "painter", "landscaper", "handyman", "appliance"],
              description: "Type of service",
            },
            phoneNumber: { type: "STRING", description: "Phone number" },
            address: { type: "STRING", description: "Full street address" },
            website: { type: "STRING", description: "Website URL" },
            rating: { type: "NUMBER", description: "Google rating (e.g. 4.7)" },
          },
          required: ["name", "category"],
        },
      },
      {
        name: "create_repair_project",
        description: "Create a new repair or home improvement project to track",
        parameters: {
          type: "OBJECT",
          properties: {
            title: { type: "STRING", description: "Project title (e.g., 'Bathroom Renovation', 'Roof Repair')" },
            description: { type: "STRING", description: "Description of the work needed" },
            category: {
              type: "STRING",
              enum: ["electrician", "plumber", "generalContractor", "roofer", "hvac", "carpenter", "painter", "landscaper", "handyman", "appliance", "other"],
              description: "Type of work",
            },
            priority: {
              type: "STRING",
              enum: ["low", "medium", "high"],
              description: "How urgently the project needs to be done",
            },
          },
          required: ["title", "description", "category"],
        },
      },
    ],
  },
];

// Proxy a single Gemini generateContent call with token enforcement.
// The iOS client manages the multi-turn function-calling loop and calls
// this function once per Gemini API call.
export const geminiChat = onCall(
  {
    enforceAppCheck: true,
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in to use hAIndyman.");
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const userRef = db.collection("users").doc(uid);

    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User record not found. Please sign out and sign in again.");
    }

    const userData = userDoc.data()!;
    const tier = (userData.tier as string) ?? "free";
    const limit = TIER_LIMITS[tier] ?? TIER_LIMITS.free;
    let used = (userData.monthlyTokensUsed as number) ?? 0;
    const aiMemory = (userData.aiMemory as string) ?? "";

    // Reset monthly usage if the billing period has rolled over
    const resetDate = (userData.tierResetDate as Timestamp)?.toDate();
    if (resetDate && new Date() > resetDate) {
      const nextReset = new Date();
      nextReset.setMonth(nextReset.getMonth() + 1);
      await userRef.update({ monthlyTokensUsed: 0, tierResetDate: nextReset });
      used = 0;
    }

    if (used >= limit) {
      throw new HttpsError(
        "resource-exhausted",
        `Monthly limit of ${limit.toLocaleString()} tokens reached. Upgrade your plan to continue.`
      );
    }

    const { contents } = request.data as { contents: unknown[] };
    if (!Array.isArray(contents) || contents.length === 0) {
      throw new HttpsError("invalid-argument", "contents must be a non-empty array.");
    }

    const systemInstruction = aiMemory
      ? `${SYSTEM_PROMPT}\n\nWhat you remember about this user:\n${aiMemory}`
      : SYSTEM_PROMPT;

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const model = genAI.getGenerativeModel({
      model: "gemini-3.5-flash",
      systemInstruction,
      tools: TOOLS as any,
    });

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const result = await model.generateContent({ contents: contents as any });
    const response = result.response;
    const tokensUsed = response.usageMetadata?.totalTokenCount ?? 0;

    await userRef.update({ monthlyTokensUsed: FieldValue.increment(tokensUsed) });

    // Extract and update memory in the background — does not block response
    const lastUserContent = (contents as any[]).slice().reverse().find((c: any) => c.role === "user");
    const userText: string = (lastUserContent?.parts as any[])?.find((p: any) => typeof p.text === "string")?.text ?? "";
    const assistantText: string = response.candidates?.[0]?.content?.parts?.find((p: any) => typeof (p as any).text === "string")?.text ?? "";
    extractAndUpdateMemory(uid, aiMemory, userText, assistantText, process.env.GEMINI_API_KEY!).catch(() => {});

    return {
      candidates: response.candidates,
      usageMetadata: response.usageMetadata,
      tokensUsed,
      totalUsed: used + tokensUsed,
      limit,
    };
  }
);

async function extractAndUpdateMemory(
  uid: string,
  currentMemory: string,
  userMessage: string,
  assistantResponse: string,
  apiKey: string
): Promise<void> {
  if (!userMessage && !assistantResponse) return;
  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-3.5-flash" });
    const prompt = `You are a memory extraction assistant. Extract personal facts about the user worth remembering for future home maintenance conversations.

Current memory: "${currentMemory || "none"}"

New exchange:
User: "${userMessage.slice(0, 400)}"
Assistant: "${assistantResponse.slice(0, 400)}"

Extract any NEW facts about: user's name, home type/age, location, family, appliances owned, recurring issues, or preferences relevant to home maintenance.

Reply ONLY with a concise updated memory (under 500 characters). If nothing new, reply with the current memory unchanged. No explanations or greetings.`;

    const memResult = await model.generateContent(prompt);
    const newMemory = memResult.response.text().trim();
    if (newMemory && newMemory !== currentMemory) {
      await getFirestore().collection("users").doc(uid).update({ aiMemory: newMemory });
    }
  } catch {
    // Non-fatal
  }
}

// Proxy for Google Places API — keeps the API key server-side.
// iOS sends { query, latitude?, longitude? } and receives the raw Places response.
export const placesSearch = onCall(
  {
    enforceAppCheck: true,
    secrets: ["GOOGLE_PLACES_API_KEY"],
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const { query, latitude, longitude, radius } = request.data as {
      query: string;
      latitude?: number;
      longitude?: number;
      radius?: number;
    };

    if (!query || typeof query !== "string") {
      throw new HttpsError("invalid-argument", "query is required.");
    }

    const apiKey = process.env.GOOGLE_PLACES_API_KEY ?? "";
    console.log(`placesSearch: query="${query}", keyLength=${apiKey.length}`);

    const fieldMask = [
      "places.id",
      "places.displayName",
      "places.formattedAddress",
      "places.nationalPhoneNumber",
      "places.websiteUri",
      "places.rating",
      "places.userRatingCount",
      "places.priceLevel",
      "places.types",
      "places.regularOpeningHours",
      "places.location",
    ].join(",");

    const body: Record<string, unknown> = { textQuery: query, maxResultCount: 20 };
    if (typeof latitude === "number" && typeof longitude === "number") {
      body.locationBias = {
        circle: {
          center: { latitude, longitude },
          radius: typeof radius === "number" ? radius : 16093.4,
        },
      };
    }

    const placesResponse = await fetch("https://places.googleapis.com/v1/places:searchText", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": fieldMask,
      },
      body: JSON.stringify(body),
    });

    if (!placesResponse.ok) {
      const errorBody = await placesResponse.text();
      console.error(`Google Places error ${placesResponse.status}:`, errorBody);
      throw new HttpsError("internal", `Google Places error ${placesResponse.status}: ${errorBody}`);
    }

    return await placesResponse.json();
  }
);

// Called by iOS after a successful StoreKit purchase to sync the tier to Firestore.
// Product IDs must match those defined in ServicesSubscriptionService.swift.
export const updateSubscriptionTier = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const { productID } = request.data as { productID: string };

    const tierMap: Record<string, string> = {
      "EstraDOS.Home-Maintainer.subscription.standard": "standard",
      "EstraDOS.Home-Maintainer.subscription.pro": "pro",
    };

    const tier = tierMap[productID];
    if (!tier) {
      throw new HttpsError("invalid-argument", `Unknown product ID: ${productID}`);
    }

    const nextReset = new Date();
    nextReset.setMonth(nextReset.getMonth() + 1);

    const db = getFirestore();
    await db.collection("users").doc(request.auth.uid).update({
      tier,
      tierResetDate: nextReset,
    });

    return { tier };
  }
);

// Called by iOS when StoreKit reports no active subscription (expired/cancelled).
export const downgradeToFree = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const db = getFirestore();
    await db.collection("users").doc(request.auth.uid).update({ tier: "free" });

    return { tier: "free" };
  }
);
