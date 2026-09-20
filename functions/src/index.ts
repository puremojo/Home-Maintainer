import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { initializeApp } from "firebase-admin/app";

initializeApp();

// Token limits must match UserSubscriptionData.tierLimits in iOS
const TIER_LIMITS: Record<string, number> = {
  free: 100_000,
  standard: 1_000_000,
  pro: 5_000_000,
};

// Places searches have a flat per-call cost (unlike variable-length Gemini tokens), so this is
// a simple monthly call count rather than a token budget. Adjust freely — these numbers aren't
// mirrored anywhere else.
const PLACES_SEARCH_LIMITS: Record<string, number> = {
  free: 10,
  standard: 50,
  pro: 200,
};

// hAIndyman now calls Gemini directly from the device via Firebase AI Logic — chat content,
// system prompts, and tool schemas live client-side (see GeminiService.swift) and never reach
// this backend. What remains here is purely the tamper-resistant quota gate: these two
// functions only ever see token counts, never prompts or responses.
//
// checkQuota reserves an estimated token cost atomically (in the same Firestore transaction as
// the limit check) so concurrent requests can't all read the same not-yet-incremented counter
// and pass simultaneously. reportUsage trues up that estimate to the real cost once the actual
// response comes back with usageMetadata.
export const checkQuota = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in to use hAIndyman.");
    }

    const { estimatedTokens } = request.data as { estimatedTokens: number };
    if (typeof estimatedTokens !== "number" || estimatedTokens <= 0) {
      throw new HttpsError("invalid-argument", "estimatedTokens must be a positive number.");
    }

    const db = getFirestore();
    const userRef = db.collection("users").doc(request.auth.uid);

    return await db.runTransaction(async (tx) => {
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User record not found. Please sign out and sign in again.");
      }

      const userData = userDoc.data()!;
      const tier = (userData.tier as string) ?? "free";
      const limit = TIER_LIMITS[tier] ?? TIER_LIMITS.free;
      let used = (userData.monthlyTokensUsed as number) ?? 0;

      // Reset monthly usage if the billing period has rolled over.
      const updates: Record<string, unknown> = {};
      const resetDate = (userData.tierResetDate as Timestamp)?.toDate();
      if (resetDate && new Date() > resetDate) {
        const nextReset = new Date();
        nextReset.setMonth(nextReset.getMonth() + 1);
        updates.tierResetDate = nextReset;
        used = 0;
      }

      if (used + estimatedTokens > limit) {
        throw new HttpsError(
          "resource-exhausted",
          `Monthly limit of ${limit.toLocaleString()} tokens reached. Upgrade your plan to continue.`
        );
      }

      // Reserve the estimate now, atomically, so a concurrent call can't slip through before
      // this one's real usage is reported back via reportUsage.
      updates.monthlyTokensUsed = used + estimatedTokens;
      tx.update(userRef, updates);

      return { allowed: true, reservedAmount: estimatedTokens };
    });
  }
);

// Trues up a checkQuota reservation to the real token cost once the client has the actual
// usageMetadata from Gemini. delta may be positive (estimate was too low) or negative (too
// high) — either way this keeps monthlyTokensUsed accurate without ever having seen content.
export const reportUsage = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const { actualTokens, reservedAmount } = request.data as {
      actualTokens: number;
      reservedAmount: number;
    };
    if (typeof actualTokens !== "number" || typeof reservedAmount !== "number") {
      throw new HttpsError("invalid-argument", "actualTokens and reservedAmount must be numbers.");
    }

    const delta = actualTokens - reservedAmount;
    if (delta !== 0) {
      const db = getFirestore();
      await db.collection("users").doc(request.auth.uid).update({
        monthlyTokensUsed: FieldValue.increment(delta),
      });
    }

    return { ok: true };
  }
);

// One-time cleanup called by the client after it has migrated the legacy aiMemory string into
// its own local, CloudKit-synced UserMemory record. Removes the plaintext field from Firestore
// so nothing lingers there post-migration. Content-blind — only deletes, never reads the value.
export const clearMigratedMemory = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const db = getFirestore();
    await db.collection("users").doc(request.auth.uid).update({
      aiMemory: FieldValue.delete(),
    });

    return { ok: true };
  }
);

// Proxy for Google Places API — keeps the API key server-side.
// iOS sends { query, latitude?, longitude? } and receives the raw Places response.
// Content-blind logging: nothing about the query text or location is ever logged here, only
// the monthly call count needed to enforce the quota below.
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

    // Atomic check-and-increment — a flat count, not an estimate/true-up pair like Gemini's
    // token quota, since every search costs the same regardless of what's searched for.
    const db = getFirestore();
    const userRef = db.collection("users").doc(request.auth.uid);
    await db.runTransaction(async (tx) => {
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User record not found. Please sign out and sign in again.");
      }

      const userData = userDoc.data()!;
      const tier = (userData.tier as string) ?? "free";
      const limit = PLACES_SEARCH_LIMITS[tier] ?? PLACES_SEARCH_LIMITS.free;
      let used = (userData.monthlyPlacesSearchesUsed as number) ?? 0;

      // Same monthly billing cycle as the Gemini token quota — reuses tierResetDate so both
      // counters roll over together instead of drifting on separate schedules.
      const updates: Record<string, unknown> = {};
      const resetDate = (userData.tierResetDate as Timestamp)?.toDate();
      if (resetDate && new Date() > resetDate) {
        const nextReset = new Date();
        nextReset.setMonth(nextReset.getMonth() + 1);
        updates.tierResetDate = nextReset;
        updates.monthlyTokensUsed = 0;
        used = 0;
      }

      if (used >= limit) {
        throw new HttpsError(
          "resource-exhausted",
          `Monthly limit of ${limit.toLocaleString()} local business searches reached. Upgrade your plan to continue.`
        );
      }

      updates.monthlyPlacesSearchesUsed = used + 1;
      tx.update(userRef, updates);
    });

    const apiKey = process.env.GOOGLE_PLACES_API_KEY ?? "";

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
