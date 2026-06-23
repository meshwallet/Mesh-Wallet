# TronGrid API Key

Mesh uses [TronGrid](https://www.trongrid.io/) for Tron mainnet (balances, history, broadcast).

## Do you need a paid "unlimited" service?

For a normal wallet app, **a free TronGrid API key is enough**:

| Tier | Limits |
|------|--------|
| **Without key** | Strict dynamic limits, frequent 403 blocks |
| **Free key** | ~100,000 requests/day, 15 requests/second |
| **Paid providers** | Only if you expect very high traffic (GetBlock, NOWNodes, etc.) |

Register at https://www.trongrid.io/ and create an API key.

## Configure in Xcode

Add multiple keys so the app can rotate and fail over on rate limits (~3× free quota):

```xml
<key>TRONGRID_API_KEYS</key>
<array>
  <string>YOUR_KEY_1</string>
  <string>YOUR_KEY_2</string>
  <string>YOUR_KEY_3</string>
</array>
```

Legacy single key still works:

```xml
<key>TRONGRID_API_KEY</key>
<string>YOUR_KEY_HERE</string>
```

The app round-robins keys and automatically switches to the next key on HTTP 403/429.

Alternatively at runtime (debug):

```swift
UserDefaults.standard.set("YOUR_KEY", forKey: "TRONGRID_API_KEY")
```
