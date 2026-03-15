# Location Services Setup Instructions

## Required: Add Location Permission to Info.plist

You need to add location usage description to your app's Info.plist file:

### Steps:
1. In Xcode, select your project in the navigator
2. Select the "Home Maintainer" target
3. Go to the "Info" tab
4. Click the "+" button to add a new key
5. Add the following key and value:

**Key:** `NSLocationWhenInUseUsageDescription`
**Value:** `We need your location to find local service providers like plumbers, electricians, and roofers near you.`

Alternatively, you can add this directly to your Info.plist file:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find local service providers like plumbers, electricians, and roofers near you.</string>
```

## How It Works

1. **Location Permission**: When you first tap on the Providers tab, the app will request permission to access your location
2. **Find Local Businesses**: In the Providers tab, you'll see a "Find Local Businesses" section with buttons for Plumbers, Electricians, and Roofers
3. **Search**: Tap any category to search for local businesses near you (within ~10 miles)
4. **Add Providers**: Review the suggestions and tap the "+" button to add them to your provider list
5. **Auto-populated Info**: The business name, phone number, and address are automatically filled in

## Features

- Uses MapKit's local search to find businesses
- Shows distance from your location
- One-tap to add businesses to your providers
- Automatically searches within a 10-mile radius
- Visual confirmation when a business is added

## Privacy

- Location is only used to search for nearby businesses
- Location data is not stored
- Only requests "When In Use" permission (not always)
