//
//  PrismStore.swift
//  Aglaia
//
//  StoreKit 2 によるステージパックの内部課金(非消耗型)。
//  購入状態は Transaction.currentEntitlements から復元する。
//

import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class PrismStore {
    /// 課金対象パックのプロダクトID一覧
    private static var allProductIDs: [String] {
        LevelPack.allCases.compactMap(\.productID)
    }

    /// App Store から取得した商品情報
    private(set) var products: [Product] = []
    /// 購入済みプロダクトID
    private(set) var purchasedProductIDs: Set<String> = []
    /// 商品情報の取得・購入処理中フラグ
    private(set) var isBusy = false
    /// 直近のエラーメッセージ(アラート表示用)
    var errorMessage: String?

    /// トランザクション更新の監視タスク
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            // App Store 側の状態変化(承認・返金・ファミリー共有など)を反映する
            for await update in Transaction.updates {
                guard let self else { break }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    // NOTE: ストアはアプリ生存期間を通じて1つだけ保持する想定のため、
    //       updatesTask の明示的なキャンセルは行わない(weak self で保持もしない)

    // MARK: - 解放判定

    /// パックが遊べる状態か(無料パックは常に true)
    func isUnlocked(_ pack: LevelPack) -> Bool {
        guard let productID = pack.productID else { return true }
        return purchasedProductIDs.contains(productID)
    }

    var unlockedPacks: Set<LevelPack> {
        Set(LevelPack.allCases.filter { isUnlocked($0) })
    }

    func product(for pack: LevelPack) -> Product? {
        guard let productID = pack.productID else { return nil }
        return products.first { $0.id == productID }
    }

    // MARK: - 商品情報・購入状態の取得

    func loadProducts() async {
        guard products.isEmpty, !Self.allProductIDs.isEmpty else { return }
        do {
            products = try await Product.products(for: Self.allProductIDs)
        } catch {
            // 商品が未登録・オフラインでもゲーム自体は遊べるようにする
            errorMessage = nil
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var purchased: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }

    // MARK: - 購入・復元

    func purchase(_ pack: LevelPack) async {
        guard let product = product(for: pack), !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    errorMessage = "購入の検証に失敗しました。時間をおいて再度お試しください。"
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入処理に失敗しました: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "購入の復元に失敗しました: \(error.localizedDescription)"
        }
    }
}
