import SwiftUI

/// Permissions settings section for site settings edit sheet.
///
/// Contains permission toggles for camera, microphone, screen sharing,
/// location, and device sensors.
struct SiteSettingsPermissionsSection: View {
    @Binding var cameraPermission: PermissionPolicy
    @Binding var microphonePermission: PermissionPolicy
    @Binding var screenSharingPermission: PermissionPolicy
    @Binding var locationPermission: PermissionPolicy
    @Binding var deviceSensorPermission: PermissionPolicy

    var body: some View {
        Section("Permissions") {
            Picker("Camera", selection: $cameraPermission) {
                ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Microphone", selection: $microphonePermission) {
                ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Screen Sharing", selection: $screenSharingPermission) {
                ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Location", selection: $locationPermission) {
                ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Device Sensors", selection: $deviceSensorPermission) {
                ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
        }
    }
}
