//
//  ChatView+ViewModel+Config.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Bootstrap and everything `/config` feeds into the view model: appearance, header imagery,
/// start prompts, product-card settings, image gate, and the in-chat banners fetch.
extension ChatView.ViewModel {

    /// Config → provider → snapshot stream → first history page.
    /// A config failure is surfaced on `phase` (retry re-enters here),
    /// a history failure is non-fatal.
    func bootstrap() async {
        self.phase = .loading

        do {
            let config = try await self.service.fetchConfig()
            await self.applyChrome(from: config)
            let page = await self.pageContext()
            self.applyStartPromptsFromConfig(config.startPrompts, page: page)
            // 401 sets `sessionEnded` then throws; swallow so bootstrap can
            // reach ready chrome and ChatView can present the session-ended alert.
            try? await self.loadBanners(url: page)
            self.applyProductCardFromConfig(config.productCard)
            self.applyImageEnabledFromConfig(config.imageEnabled)

            let provider = self.makeProvider(
                self.service,
                self.pageContext,
                config.display.welcomeMessage,
                self.offersAttachments
            )

            self.provider = provider
            self.observe(provider)

            // Flip to ready before history so a cancelled `.task` mid-`loadOlder` still
            // leaves the chrome on screen; history fills in when the load finishes.
            self.phase = .ready
            _ = try? await provider.loadOlder()

        } catch {
            self.phase = .failed
        }
    }

    /// Header imagery, font and palette — the parts of `/config` that paint chrome.
    private func applyChrome(from config: ChatConfig) async {
        self.avatar = await self.loadImage(config.display.avatar.url, maxPixelSize: 200)
        self.logo = await self.loadImage(config.theme.header.logo.url, maxPixelSize: 600)
            .map { HeaderLogo(image: $0, alignment: config.theme.header.alignment) }
        let fontFamily = await FontLoader.loadFamily(
            url: config.theme.font.ios.assetUrl,
            sha256: config.theme.font.ios.sha256,
            format: config.theme.font.ios.format,
            fetch: { [service = self.service] in try await service.fetchData($0) }
        )
        self.appearance = ChatAppearance(config, fontFamily: fontFamily)
        self.name = config.display.name
        self.subtitle = config.display.subtitle.map { Subtitle($0) }
        self.privacyPolicyURL = config.display.privacyPolicyUrl
    }

    /// Pre-loads a config image once, downsampled, so it isn't re-fetched during rendering.
    private func loadImage(_ url: URL?, maxPixelSize: CGFloat) async -> Image? {
        guard
            let url,
            let data = try? await self.service.fetchData(url)
        else {
            return nil
        }
        return RemoteImage.decode(data, maxPixelSize: maxPixelSize)
    }

    // MARK: Start prompts

    /// Filters config rows for the current page — the same path `bootstrap()` uses after
    /// awaiting `contextProvider` once. Matching is a literal substring of that page string
    /// against each `url_pattern`; it does not re-run on send.
    func applyStartPromptsFromConfig(_ prompts: [StartPrompt], page: String?) {
        self.startPrompts = StartPromptMatching.select(prompts, page: page)
    }

    /// Test seam — sets the filtered start-prompt list without going through `/config`.
    func setStartPromptsForTesting(_ prompts: [StartPrompt]) {
        self.startPrompts = prompts
    }

    // MARK: Banners

    /// Fetches in-chat banners for `page`. Soft-fails to an empty list on transport /
    /// missing-route / decode so an older API does not brick bootstrap. A 401
    /// surfaces as ``ChatView.SessionEnded`` (same path as send / export).
    func loadBanners(url: String?) async throws(ChatView.SessionEnded) {
        do {
            self.banners = try await self.service.fetchBanners(url: url)
        } catch ChatServiceError.sessionExpired {
            self.banners = []
            self.sessionEnded = true
            throw ChatView.SessionEnded()
        } catch {
            self.banners = []
        }
    }

    /// Test seam — installs banners without hitting the network.
    func setBannersForTesting(_ banners: [ChatBanner]) {
        self.banners = banners
    }

    /// Hides a dismissible banner for the rest of this session (content fingerprint).
    func dismissBanner(_ banner: ChatBanner) {
        self.dismissedBannerFingerprints.insert(banner.contentFingerprint)
    }

    // MARK: Feature gates

    /// Copies `/config` `image_enabled` — call before ``makeProvider`` so upload-prompt
    /// ingestion sees the same gate as the composer button.
    func applyImageEnabledFromConfig(_ enabled: Bool) {
        self.chatbotImageEnabled = enabled
    }

    /// Copies product-card settings from `/config`. The cart button also needs a per-card sku
    /// plus either ``onAddToCart`` or a link-mode cart URL
    /// (see ``ProductGridView/shouldOfferCart(for:cartEnabled:onAddToCart:)``).
    func applyProductCardFromConfig(_ settings: ProductCardSettings) {
        self.productOpenLabel = settings.openLabel
        self.cartEnabledByConfig = settings.addToCart.enabled
    }

    /// Test seam — sets product-card CTA state without going through `/config`.
    func setProductCardForTesting(openLabel: String?, addToCartEnabled: Bool) {
        self.applyProductCardFromConfig(
            ProductCardSettings(openLabel: openLabel, addToCartEnabled: addToCartEnabled)
        )
    }
}
