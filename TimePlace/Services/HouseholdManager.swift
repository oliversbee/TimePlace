import Foundation
import Supabase

struct Household: Codable, Identifiable {
    let id: UUID
    let name: String
    let joinCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case joinCode = "join_code"
    }
}

struct PairedDevice: Identifiable, Codable {
    var id: String { deviceId }

    let deviceId: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        deviceId = try container.decode(
            String.self,
            forKey: .deviceId
        )

        name = try container.decodeIfPresent(
            String.self,
            forKey: .name
        ) ?? "E-Paper Display"
    }
}

@MainActor
final class HouseholdManager: ObservableObject {

    @Published var households: [Household] = []
    @Published var pairedDevices: [PairedDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client

    // MARK: - Households

    func fetchHouseholds() async {
        isLoading = true
        errorMessage = nil

        do {
            households = try await client
                .from("households")
                .select()
                .execute()
                .value
        } catch {
            print("Failed to load households:", error)

            errorMessage = "Failed to load households."
        }

        isLoading = false
    }

    // MARK: - Create Household

    func createHousehold(name: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            struct CreateHouseholdParams: Encodable {
                let p_name: String
            }

            let created: Household = try await client
                .rpc(
                    "create_household",
                    params: CreateHouseholdParams(
                        p_name: name
                    )
                )
                .execute()
                .value

            households.append(created)

            isLoading = false
            return true

        } catch {
            print("Failed to create household:", error)

            errorMessage = "Failed to create household."

            isLoading = false
            return false
        }
    }

    // MARK: - Join Household

    func joinHousehold(code: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            struct JoinParams: Encodable {
                let p_join_code: String
            }

            let _: UUID = try await client
                .rpc(
                    "join_household",
                    params: JoinParams(
                        p_join_code: code
                    )
                )
                .execute()
                .value

            await fetchHouseholds()

            isLoading = false
            return true

        } catch {
            print("Failed to join household:", error)

            errorMessage = "Invalid join code or failed to join."

            isLoading = false
            return false
        }
    }

    // MARK: - Devices

    func fetchPairedDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            pairedDevices = try await client
                .from("device_claims")
                .select("device_id")
                .not(
                    "assigned_user_id",
                    operator: .is,
                    value: "null"
                )
                .execute()
                .value

        } catch {
            print("Failed to load paired devices:", error)

            errorMessage = "Failed to load paired devices."
        }

        isLoading = false
    }

    // MARK: - Pair Device

    func pairDevice(claimCode: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        guard let userId = client.auth.currentUser?.id else {
            errorMessage = "Not authenticated."

            isLoading = false
            return false
        }

        do {
            struct UpdateClaim: Encodable {
                let assigned_user_id: UUID
            }

            try await client
                .from("device_claims")
                .update(
                    UpdateClaim(
                        assigned_user_id: userId
                    )
                )
                .eq(
                    "claim_code",
                    value: claimCode
                        .uppercased()
                        .trimmingCharacters(
                            in: .whitespaces
                        )
                )
                .execute()

            isLoading = false
            return true

        } catch {
            print("Failed to pair device:", error)

            errorMessage =
                "Failed to pair device. Code may be expired or invalid."

            isLoading = false
            return false
        }
    }
}
