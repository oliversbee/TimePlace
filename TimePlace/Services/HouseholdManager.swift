import Foundation
import Supabase

// MARK: - Household

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


// MARK: - Household Member

struct HouseholdMember: Codable, Identifiable {
    let userId: UUID
    let name: String?

    var id: UUID {
        userId
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
    }
}


// MARK: - Nickname

struct UserNickname: Codable {
    let viewerId: UUID
    let targetId: UUID
    let nickname: String

    enum CodingKeys: String, CodingKey {
        case viewerId = "viewer_id"
        case targetId = "target_id"
        case nickname
    }
}

// MARK: - Paired Device

struct PairedDevice: Identifiable, Codable {
    var id: String {
        deviceId
    }

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


// MARK: - Household Manager

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


    // MARK: - Household Members

    func fetchHouseholdMembers(
        householdId: UUID
    ) async -> [HouseholdMember] {

        do {

            struct MemberRow: Decodable {
                let userId: UUID
                let user: UserProfile?

                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case user
                }
            }

            struct UserProfile: Decodable {
                let id: UUID
                let name: String?
            }

            let rows: [MemberRow] = try await client
                .from("household_members")
                .select(
                    """
                    user_id,
                    users (
                        id,
                        name
                    )
                    """
                )
                .eq(
                    "household_id",
                    value: householdId
                )
                .execute()
                .value

            return rows.map {
                HouseholdMember(
                    userId: $0.userId,
                    name: $0.user?.name
                )
            }

        } catch {

            print(
                "Failed to load household members:",
                error
            )

            return []
        }
    }


    // MARK: - Nicknames

    func fetchNicknames() async -> [UUID: String] {

        guard let userId = client.auth.currentUser?.id else {
            return [:]
        }

        do {

            let nicknames: [UserNickname] = try await client
                .from("nicknames")
                .select()
                .eq(
                    "viewer_id",
                    value: userId
                )
                .execute()
                .value

            var result: [UUID: String] = [:]

            for nickname in nicknames {
                result[nickname.targetId] = nickname.nickname
            }

            return result

        } catch {

            print(
                "Failed to load nicknames:",
                error
            )

            return [:]
        }
    }


    // MARK: - Set Nickname

    func setNickname(
        targetUserId: UUID,
        nickname: String
    ) async -> Bool {

        guard let viewerId = client.auth.currentUser?.id else {
            errorMessage = "Not authenticated."
            return false
        }

        let trimmedNickname = nickname
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {

            // Delete any existing nickname first.
            // This avoids relying on a unique constraint that
            // does not currently exist on viewer_id + target_id.

            try await client
                .from("nicknames")
                .delete()
                .eq(
                    "viewer_id",
                    value: viewerId
                )
                .eq(
                    "target_id",
                    value: targetUserId
                )
                .execute()


            // Empty nickname means "use their normal name".
            if trimmedNickname.isEmpty {
                return true
            }


            struct NewNickname: Encodable {
                let viewer_id: UUID
                let target_id: UUID
                let nickname: String
            }

            try await client
                .from("nicknames")
                .insert(
                    NewNickname(
                        viewer_id: viewerId,
                        target_id: targetUserId,
                        nickname: trimmedNickname
                    )
                )
                .execute()

            return true

        } catch {

            print(
                "Failed to update nickname:",
                error
            )

            errorMessage = "Failed to update nickname."

            return false
        }
    }


// MARK: - Hidden Users

func fetchHiddenUsers() async -> Set<UUID> {

    guard let userId = client.auth.currentUser?.id else {
        return []
    }

    do {

        struct HiddenUserRow: Decodable {
            let hiddenUserId: UUID

            enum CodingKeys: String, CodingKey {
                case hiddenUserId = "hidden_user_id"
            }
        }

        let hiddenUsers: [HiddenUserRow] = try await client
            .from("hidden_users")
            .select("hidden_user_id")
            .eq(
                "user_id",
                value: userId
            )
            .execute()
            .value

        return Set(
            hiddenUsers.map {
                $0.hiddenUserId
            }
        )

    } catch {

        print(
            "Failed to load hidden users:",
            error
        )

        return []
    }
}


// MARK: - Hide User

func hideUser(
    targetUserId: UUID
) async -> Bool {

    guard let userId = client.auth.currentUser?.id else {
        errorMessage = "Not authenticated."
        return false
    }

    do {

        struct HiddenUserInsert: Encodable {
            let user_id: UUID
            let hidden_user_id: UUID
        }

        try await client
            .from("hidden_users")
            .insert(
                HiddenUserInsert(
                    user_id: userId,
                    hidden_user_id: targetUserId
                )
            )
            .execute()

        return true

    } catch {

        print(
            "Failed to hide user:",
            error
        )

        errorMessage = "Failed to hide user."

        return false
    }
}


// MARK: - Unhide User

func unhideUser(
    targetUserId: UUID
) async -> Bool {

    guard let userId = client.auth.currentUser?.id else {
        errorMessage = "Not authenticated."
        return false
    }

    do {

        try await client
            .from("hidden_users")
            .delete()
            .eq(
                "user_id",
                value: userId
            )
            .eq(
                "hidden_user_id",
                value: targetUserId
            )
            .execute()

        return true

    } catch {

        print(
            "Failed to unhide user:",
            error
        )

        errorMessage = "Failed to unhide user."

        return false
    }
}


    // MARK: - Leave Household

    func leaveHousehold(
        householdId: UUID
    ) async -> Bool {

        isLoading = true
        errorMessage = nil

        do {

            struct LeaveHouseholdParams: Encodable {
                let p_household_id: UUID
            }

            let _: Bool = try await client
                .rpc(
                    "leave_household",
                    params: LeaveHouseholdParams(
                        p_household_id: householdId
                    )
                )
                .execute()
                .value

            // Remove the household from the current UI.
            households.removeAll {
                $0.id == householdId
            }

            isLoading = false
            return true

        } catch {

            print(
                "Failed to leave household:",
                error
            )

            errorMessage = "Failed to leave household."

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

            print(
                "Failed to load paired devices:",
                error
            )

            errorMessage = "Failed to load paired devices."
        }

        isLoading = false
    }


    // MARK: - Pair Device

    func pairDevice(
        claimCode: String
    ) async -> Bool {

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

            print(
                "Failed to pair device:",
                error
            )

            errorMessage =
                "Failed to pair device. Code may be expired or invalid."

            isLoading = false
            return false
        }
    }
}