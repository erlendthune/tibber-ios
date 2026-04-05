import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to Tibber Dashboard")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)
                    
                    Group {
                        Text("Getting Started")
                            .font(.headline)
                        Text("To use this app, you need a Tibber API key and the Home ID belonging to your property. Enter these in the Settings (gear icon). You can automatically fetch your Home IDs once your API key is provided.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Power Ring & Metrics")
                            .font(.headline)
                        Text("The main circle displays your energy consumption for the current hour. The ring fills up and changes color based on your configured Critical limit:")
                        HStack {
                            Circle().fill(Color.green).frame(width: 15, height: 15)
                            Text("Normal (Below limit)")
                        }
                        HStack {
                            Circle().fill(Color.red).frame(width: 15, height: 15)
                            Text("Critical (At or above limit)")
                        }
                        Text("Inside the ring you'll see: accumulated kWh consumed, time remaining in the hour, live power draw, remaining headroom before reaching your limit, and your configured limit.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Screensaver")
                            .font(.headline)
                        Text("To prevent screen burn-in on always-on displays, the app automatically turns the screen black after a period of inactivity. This is configurable in Settings. You can also tap anywhere on the screen while the app is active to instantly hide the dashboard, or tap the black screen to wake it back up.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Audio Alarms")
                            .font(.headline)
                        Text("If your hour average breaches your Critical threshold, an alarm sound will play to notify you, even if the screen is black.")
                    }

                    Divider()

                    Group {
                        Text("Telegram Alerts")
                            .font(.headline)
                        Text("You can receive Telegram alerts when a critical threshold is triggered. Go to Settings and open Telegram (Optional).")
                        Text("1. Find your bot token: open BotFather in Telegram, create/select your bot, and copy the HTTP API token.")
                        Text("2. Find your chat/user ID: start a conversation with your bot, then use getUpdates (or a Telegram ID bot) to read your chat id and add it as a recipient in Settings.")
                        Text("Important: each recipient must send at least one message to tun_dashboard_bot before the bot can send alerts to that chat.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Zaptec Charger Integration")
                            .font(.headline)
                        Text("You can control your Zaptec EV charger directly from the dashboard. Go to Settings, enter your Zaptec credentials and Installation ID. From the dashboard, you can monitor charge status, resume/pause charging, and adjust the available current limit. Please note that Zaptec restricts adjusting current limits to a maximum of once every 15 minutes.")
                    }
                    
                    Divider()
                    
                    Group {
                        Text("Philips Hue Lights")
                            .font(.headline)
                        Text("You can synchronize your Philips Hue smart lights to visually indicate your power consumption level, including flashing the lights when a critical threshold is breached. To use this, go to Settings, discover your Bridge on your local network, tap the physical button on the bridge, and link it. You can enable or disable light flashing using the toggle in Settings.")
                    }
                }
                .padding()
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
