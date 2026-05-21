import Foundation

/// Registry of OAuth provider domains and authentication patterns.
///
/// `OAuthDomainRegistry` identifies URLs involved in OAuth and authentication flows
/// to ensure they receive proper user agent handling and aren't interrupted by
/// privacy features.
///
/// ## Purpose
///
/// OAuth flows are sensitive to:
/// - User agent strings (providers may reject non-Safari browsers)
/// - Cookie blocking (breaks session continuity)
/// - Redirect interception (breaks OAuth callback flow)
///
/// This registry helps identify these flows early so they can be handled correctly.
///
/// ## Supported Providers
///
/// - Google (accounts.google.com, oauth2)
/// - Microsoft (login.microsoftonline.com, Azure AD)
/// - Apple (appleid.apple.com)
/// - Facebook (facebook.com/dialog/oauth)
/// - GitHub (github.com/login/oauth)
/// - Twitter/X (api.twitter.com/oauth)
/// - LinkedIn (linkedin.com/oauth)
/// - Amazon (amazon.com/ap/oa)
/// - Atlassian (auth.atlassian.com)
/// - Okta, Auth0, and other identity providers
///
/// ## Usage
///
/// ```swift
/// if OAuthDomainRegistry.isOAuthDomain(url.host) {
///     // Use Safari UA, don't block cookies
/// }
///
/// if OAuthDomainRegistry.isOAuthFlow(url) {
///     // Active OAuth redirect, handle carefully
/// }
/// ```
enum OAuthDomainRegistry {
    // MARK: - Domain Checking

    /// Checks if a host belongs to an OAuth provider.
    ///
    /// - Parameter host: The domain host to check.
    /// - Returns: `true` if this is a known OAuth provider domain.
    static func isOAuthDomain(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }

        // Check exact matches first
        if oauthDomains.contains(host) {
            return true
        }

        // Check suffix matches (e.g., "auth.company.okta.com")
        return oauthDomainSuffixes.contains { host.hasSuffix($0) }
    }

    /// Checks if a URL is part of an active OAuth flow.
    ///
    /// This is more specific than `isOAuthDomain` — it checks for actual
    /// OAuth endpoints and patterns, not just the domain.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if this appears to be an OAuth flow URL.
    static func isOAuthFlow(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Check domain-specific OAuth patterns
        if let patterns = oauthPathPatterns[host] {
            let path = url.path.lowercased()
            return patterns.contains { path.contains($0) }
        }

        // Check for subdomains of OAuth providers
        for (domain, patterns) in oauthPathPatterns {
            if host.hasSuffix(".\(domain)") || host == domain {
                let path = url.path.lowercased()
                if patterns.contains(where: { path.contains($0) }) {
                    return true
                }
            }
        }

        // Check generic OAuth indicators in query string
        let query = url.query?.lowercased() ?? ""
        return genericOAuthIndicators.contains { query.contains($0) }
    }

    /// Determines if a URL should bypass privacy protection handlers.
    ///
    /// Returns true for:
    /// - Known OAuth provider domains
    /// - URLs with OAuth query parameters
    /// - Payment processing domains
    static func shouldBypassPrivacyProtection(_ url: URL) -> Bool {
        if isOAuthDomain(url.host) {
            return true
        }

        if isOAuthFlow(url) {
            return true
        }

        if isPaymentDomain(url.host) {
            return true
        }

        return false
    }

    /// Known payment processor domains that shouldn't have URLs modified.
    static func isPaymentDomain(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }

        // Check exact matches first (faster for common cases)
        if paymentDomains.contains(host) {
            return true
        }

        // Check suffix matches for payment provider subdomains
        return paymentDomainSuffixes.contains { host.hasSuffix($0) }
    }

    // MARK: - Payment Domain Lists

    /// Known payment processor domains (exact match).
    private static let paymentDomains: Set<String> = [
        // Stripe
        "checkout.stripe.com",
        "js.stripe.com",
        "m.stripe.com",
        "dashboard.stripe.com",

        // PayPal (international)
        "paypal.com",
        "www.paypal.com",
        "paypal.me",
        "venmo.com",

        // Apple/Google Pay
        "pay.google.com",
        "pay.apple.com",
        "wallet.apple.com",

        // Authorize.net
        "secure.authorize.net",
        "accept.authorize.net",

        // Square
        "squareup.com",
        "cash.app",

        // Klarna (Sweden, EU)
        "klarna.com",
        "www.klarna.com",
        "app.klarna.com",
        "pay.klarna.com",

        // Affirm
        "affirm.com",
        "www.affirm.com",

        // Afterpay / Clearpay
        "afterpay.com",
        "www.afterpay.com",
        "clearpay.co.uk",

        // European payment providers
        "ideal.nl", // iDEAL (Netherlands)
        "www.ideal.nl",
        "bancontact.com", // Bancontact (Belgium)
        "www.bancontact.com",
        "sofort.com", // Sofort/Klarna (Germany)
        "www.sofort.com",
        "giropay.de", // Giropay (Germany)
        "www.giropay.de",
        "eps.or.at", // EPS (Austria)
        "przelewy24.pl", // Przelewy24 (Poland)
        "www.przelewy24.pl",
        "blik.pl", // BLIK (Poland)
        "multibanco.pt", // Multibanco (Portugal)
        "mbway.pt", // MB Way (Portugal)
        "trustly.com", // Trustly (Nordics)
        "www.trustly.com",
        "swish.nu", // Swish (Sweden)

        // Asian payment providers
        "alipay.com", // Alipay (China)
        "www.alipay.com",
        "global.alipay.com",
        "intl.alipay.com",
        "pay.weixin.qq.com", // WeChat Pay
        "wx.tenpay.com",
        "paytm.com", // Paytm (India)
        "www.paytm.com",
        "secure.paytm.in",
        "razorpay.com", // Razorpay (India)
        "checkout.razorpay.com",
        "api.razorpay.com",
        "payu.in", // PayU (India)
        "secure.payu.in",
        "phonepe.com", // PhonePe (India)
        "www.phonepe.com",
        "linepay.line.me", // LINE Pay (Japan/Taiwan)
        "pay.line.me",
        "paypay.ne.jp", // PayPay (Japan)
        "www.paypay.ne.jp",
        "pay.rakuten.co.jp", // Rakuten Pay (Japan)
        "kakaopay.com", // Kakao Pay (Korea)
        "www.kakaopay.com",
        "naverpay.com", // Naver Pay (Korea)
        "pay.naver.com",
        "toss.im", // Toss (Korea)
        "www.toss.im",
        "grabpay.com", // GrabPay (Southeast Asia)
        "www.grabpay.com",
        "pay.grab.com",
        "gopay.co.id", // GoPay (Indonesia)
        "www.gopay.co.id",
        "www.doku.com", // DOKU (Indonesia)
        "gcash.com", // GCash (Philippines)
        "www.gcash.com",
        "maya.ph", // Maya (Philippines)
        "www.maya.ph",
        "promptpay.io", // PromptPay (Thailand)

        // Latin America
        "mercadopago.com", // MercadoPago
        "www.mercadopago.com",
        "mercadopago.com.br",
        "mercadopago.com.ar",
        "mercadopago.com.mx",
        "pix.bcb.gov.br", // PIX (Brazil)
        "nubank.com.br", // Nubank (Brazil)
        "www.nubank.com.br",
        "oxxo.com", // OXXO (Mexico)
        "pse.com.co", // PSE (Colombia)

        // Cryptocurrency (common on e-commerce)
        "commerce.coinbase.com",
        "bitpay.com",
        "www.bitpay.com",

        // Middle East / Africa
        "payfort.com", // PayFort (UAE)
        "www.payfort.com",
        "checkout.payfort.com",
        "paystack.com", // Paystack (Africa)
        "checkout.paystack.com",
        "flutterwave.com", // Flutterwave (Africa)
        "checkout.flutterwave.com",
        "mtn.com", // MTN Mobile Money
        "www.pesapal.com", // PesaPal (East Africa)
        "mpesa.com", // M-Pesa

        // Russia / CIS
        "yoomoney.ru", // YooMoney (ex-Yandex.Money)
        "www.yoomoney.ru",
        "payment.yandex.ru",
        "qiwi.com", // QIWI
        "www.qiwi.com",
        "paymentpage.qiwi.com",
        "webmoney.ru", // WebMoney
        "www.webmoney.ru",
        "sberbank.ru", // Sberbank
        "online.sberbank.ru",
        "securepayments.sberbank.ru",
        "tinkoff.ru", // Tinkoff
        "www.tinkoff.ru",
        "securepay.tinkoff.ru",

        // ANZ region
        "poli.to", // POLi (Australia/NZ)
        "www.polipayments.com",
        "afterpay.com.au",
        "zip.co", // Zip (Australia)
        "www.zip.co",
    ]

    /// Payment provider domain suffixes.
    private static let paymentDomainSuffixes: Set<String> = [
        // Payment gateways
        ".adyen.com",
        ".braintreegateway.com",
        ".braintree-api.com",
        ".worldpay.com",
        ".worldline.com",
        ".checkout.com",
        ".2checkout.com",
        ".verifone.com",
        ".cybersource.com",
        ".paymentwall.com",
        ".paddle.com",
        ".fastspring.com",
        ".chargebee.com",
        ".recurly.com",
        ".gocardless.com",
        ".mollie.com",

        // 3D Secure authentication
        ".3dsecure.net",
        ".3ds.io",
        ".3dsintegrator.com",
        ".arcot.com", // CA/Broadcom 3DS
        ".actividentity.com",
        ".cardinal.com", // Cardinal Commerce (Visa)
        ".cardinalcommerce.com",
        ".secure3d.net",
        ".securetrading.com",
        ".globalpaymentsinc.com",
        ".paymentsense.com",
        ".verifiedbyvisa.com",
        ".mastercardsecurecode.com",
        ".americanexpress.com", // AmEx SafeKey
        ".safekey.com",
        ".jcbcard.com",
        ".dinersclub.com",
        ".discover.com",

        // US Banks
        ".bankofamerica.com",
        ".chase.com",
        ".wellsfargo.com",
        ".citi.com",
        ".capitalone.com",
        ".usbank.com",
        ".pnc.com",

        // UK Banks
        ".hsbc.com",
        ".hsbc.co.uk",
        ".barclays.com",
        ".barclays.co.uk",
        ".barclaycard.com",
        ".barclaycard.co.uk",
        ".lloydsbank.com",
        ".halifax.co.uk",
        ".bankofscotland.co.uk",
        ".natwest.com",
        ".rbs.co.uk",
        ".santander.co.uk",
        ".nationwide.co.uk",
        ".tsb.co.uk",
        ".metro.bank",
        ".monzo.com",
        ".starlingbank.com",
        ".revolut.com",

        // German Banks
        ".deutschebank.de",
        ".deutsche-bank.de",
        ".commerzbank.de",
        ".postbank.de",
        ".sparkasse.de",
        ".volksbank.de",
        ".hypovereinsbank.de",
        ".dkb.de",
        ".ing.de",
        ".n26.com",
        ".comdirect.de",
        ".consorsbank.de",
        ".targobank.de",

        // French Banks
        ".bnpparibas.com",
        ".bnpparibas.fr",
        ".mabanque.bnpparibas",
        ".credit-agricole.fr",
        ".ca-paris.fr",
        ".ca-centrest.fr",
        ".societegenerale.com",
        ".societegenerale.fr",
        ".labanquepostale.fr",
        ".banquepostale.fr",
        ".lcl.fr",
        ".lcl.com",
        ".creditmutuel.fr",
        ".credit-mutuel.fr",
        ".cic.fr",
        ".caisse-epargne.fr",
        ".banquepopulaire.fr",
        ".boursorama.com",
        ".boursobank.com",
        ".fortuneo.fr",
        ".ing.fr",
        ".hsbc.fr",
        ".axabanque.fr",
        ".hellobank.fr",
        ".monabanq.com",
        ".bforbank.com",
        ".orangebank.fr",

        // Spanish Banks
        ".santander.com",
        ".santander.es",
        ".bancosantander.es",
        ".bbva.com",
        ".bbva.es",
        ".caixabank.es",
        ".caixabank.com",
        ".lacaixa.es",
        ".bankia.es",
        ".bankinter.com",
        ".bankinter.es",
        ".sabadell.com",
        ".bancsabadell.com",
        ".unicaja.es",
        ".unicajabanco.es",
        ".kutxabank.es",
        ".ibercaja.es",
        ".abanca.com",
        ".liberbank.es",
        ".openbank.es",
        ".ing.es",
        ".deutschebank.es",
        ".evo.es",
        ".wizink.es",

        // Italian Banks
        ".unicredit.it",
        ".unicredit.eu",
        ".intesasanpaolo.com",
        ".intesasanpaolo.it",
        ".gruppointesasanpaolo.com",
        ".bnl.it",
        ".bnlmail.com",
        ".mps.it", // Monte dei Paschi
        ".gruppomps.it",
        ".ubibanca.it",
        ".ubibanca.com",
        ".bancobpm.it",
        ".credem.it",
        ".bfrancese.it", // Banca Francese (Crédit Agricole Italia)
        ".credit-agricole.it",
        ".mediolanum.it",
        ".bancamediolanum.it",
        ".finecobank.com",
        ".fineco.it",
        ".poste.it", // Poste Italiane / BancoPosta
        ".bancoposta.it",
        ".postepay.it",
        ".chebanca.it",
        ".illimitybank.com",
        ".hype.it",
        ".n26.it",
        ".buddybank.com",
        ".ing.it",
        ".webank.it",
        ".widiba.it",

        // Portuguese Banks
        ".bpi.pt",
        ".bancobpi.pt",
        ".millenniumbcp.pt",
        ".novobanco.pt",
        ".cgd.pt", // Caixa Geral de Depósitos
        ".caixadirecta.cgd.pt",
        ".santandertotta.pt",
        ".bankinter.pt",
        ".activobank.pt",

        // Dutch Banks
        ".ing.com",
        ".ing.nl",
        ".rabobank.nl",
        ".rabobank.com",
        ".abnamro.nl",
        ".abnamro.com",
        ".sns.nl",
        ".asnbank.nl",
        ".triodos.nl",
        ".knab.nl",
        ".bunq.com",

        // Belgian Banks
        ".kbc.be",
        ".belfius.be",
        ".bnpparibasfortis.be",
        ".ing.be",
        ".argenta.be",
        ".crelan.be",

        // Nordic Banks
        ".dnb.no",
        ".nordea.com",
        ".nordea.fi",
        ".nordea.se",
        ".nordea.dk",
        ".swedbank.com",
        ".swedbank.se",
        ".swedbank.lt",
        ".swedbank.lv",
        ".swedbank.ee",
        ".handelsbanken.com",
        ".handelsbanken.se",
        ".seb.se",
        ".seb.lt",
        ".seb.lv",
        ".seb.ee",
        ".danskebank.dk",
        ".danskebank.com",
        ".jyskebank.dk",
        ".nykredit.dk",
        ".sparebank1.no",
        ".op.fi", // OP Financial Group (Finland)

        // Swiss Banks
        ".ubs.com",
        ".credit-suisse.com",
        ".zkb.ch",
        ".postfinance.ch",
        ".raiffeisen.ch",

        // Austrian Banks
        ".erstebank.at",
        ".sparkasse.at",
        ".raiffeisen.at",
        ".bawag.com",
        ".easybank.at",

        // Canadian Banks
        ".td.com",
        ".rbc.com",
        ".scotiabank.com",
        ".bmo.com",
        ".cibc.com",
        ".tangerine.ca",
        ".simplii.com",
        ".desjardins.com",
        ".nbc.ca",

        // Australian Banks
        ".nab.com.au",
        ".commbank.com.au",
        ".westpac.com.au",
        ".anz.com.au",
        ".anz.co.nz",
        ".suncorp.com.au",
        ".macquarie.com.au",
        ".bankwest.com.au",
        ".ing.com.au",
        ".ubank.com.au",
        ".86400.com.au",
        ".upbank.com.au",
    ]

    /// Checks if a URL is a two-factor authentication challenge.
    ///
    /// 2FA flows should not be interrupted or have their cookies cleared.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if this appears to be a 2FA challenge.
    static func is2FAFlow(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()

        // Google 2FA
        if host.contains("google.com"), path.contains("/challenge") {
            return true
        }

        // Microsoft 2FA
        if host.contains("microsoftonline.com"), path.contains("/common/oauth2") {
            return true
        }

        // Duo Security
        if host.contains("duosecurity.com") {
            return true
        }

        // Amazon 2FA
        if host.contains("amazon.com"), path.contains("/ap/challenge") || path.contains("/ap/cvf") {
            return true
        }

        // Generic MFA indicators
        return path.contains("/mfa") || path.contains("/2fa") || path.contains("/verify")
    }

    /// Checks if a URL is an SSO (Single Sign-On) flow.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if this appears to be an SSO flow.
    static func isSSOFlow(_ url: URL) -> Bool {
        let path = url.path.lowercased()

        // SAML SSO
        if path.contains("/saml") || path.contains("/sso") {
            return true
        }

        // OpenID Connect
        if path.contains("/openid") || path.contains("/.well-known/openid") {
            return true
        }

        return false
    }

    // MARK: - Provider Detection

    /// Identifies the OAuth provider for a URL.
    ///
    /// - Parameter url: The URL to analyze.
    /// - Returns: The provider name, or `nil` if not recognized.
    static func provider(for url: URL) -> OAuthProvider? {
        guard let host = url.host?.lowercased() else { return nil }

        for provider in OAuthProvider.allCases {
            if provider.domains.contains(where: { host.hasSuffix($0) }) {
                return provider
            }
        }

        return nil
    }

    // MARK: - Domain Lists

    /// Known OAuth provider domains (exact match).
    private static let oauthDomains: Set<String> = [
        // Google
        "accounts.google.com",
        "accounts.youtube.com",

        // Microsoft
        "login.microsoftonline.com",
        "login.live.com",
        "login.microsoft.com",

        // Apple
        "appleid.apple.com",

        // Facebook/Meta
        "www.facebook.com",
        "facebook.com",

        // GitHub
        "github.com",

        // Twitter/X
        "api.twitter.com",
        "twitter.com",
        "api.x.com",
        "x.com",

        // LinkedIn
        "www.linkedin.com",
        "linkedin.com",

        // Amazon (international)
        "www.amazon.com",
        "amazon.com",
        "www.amazon.co.uk",
        "www.amazon.de",
        "www.amazon.fr",
        "www.amazon.es",
        "www.amazon.it",
        "www.amazon.nl",
        "www.amazon.co.jp",
        "www.amazon.ca",
        "www.amazon.com.au",
        "www.amazon.in",
        "www.amazon.com.br",
        "www.amazon.com.mx",
        "www.amazon.sg",
        "www.amazon.ae",
        "www.amazon.sa",
        "www.amazon.pl",
        "www.amazon.se",
        "www.amazon.com.tr",

        // Atlassian
        "auth.atlassian.com",
        "id.atlassian.com",

        // Dropbox
        "www.dropbox.com",
        "dropbox.com",

        // Salesforce
        "login.salesforce.com",

        // Slack
        "slack.com",

        // Discord
        "discord.com",
        "discordapp.com",

        // Spotify
        "accounts.spotify.com",

        // Twitch
        "id.twitch.tv",
        "www.twitch.tv",

        // Reddit
        "www.reddit.com",
        "reddit.com",

        // Pinterest
        "api.pinterest.com",
        "www.pinterest.com",

        // Snapchat
        "accounts.snapchat.com",

        // TikTok
        "www.tiktok.com",

        // Adobe
        "ims-na1.adobelogin.com",
        "adobeid-na1.services.adobe.com",

        // Zoom
        "zoom.us",

        // Notion
        "api.notion.com",
        "www.notion.so",

        // Figma
        "www.figma.com",

        // GitLab
        "gitlab.com",

        // Bitbucket
        "bitbucket.org",

        // StackOverflow
        "stackoverflow.com",
        "stackexchange.com",

        // Yahoo / AOL
        "login.yahoo.com",
        "api.login.yahoo.com",
        "login.aol.com",

        // Yandex (Russia)
        "oauth.yandex.com",
        "oauth.yandex.ru",
        "passport.yandex.com",
        "passport.yandex.ru",

        // VK (Russia)
        "oauth.vk.com",
        "vk.com",

        // Mail.ru (Russia)
        "oauth.mail.ru",
        "o2.mail.ru",

        // Baidu (China)
        "openapi.baidu.com",
        "passport.baidu.com",

        // Weibo (China)
        "api.weibo.com",
        "weibo.com",

        // QQ / WeChat (China)
        "graph.qq.com",
        "open.weixin.qq.com",
        "open.work.weixin.qq.com",

        // Douyin / ByteDance (China)
        "open.douyin.com",

        // LINE (Japan/Taiwan/Thailand)
        "access.line.me",
        "api.line.me",

        // Yahoo Japan
        "auth.login.yahoo.co.jp",

        // Rakuten (Japan)
        "grp01.id.rakuten.co.jp",

        // Kakao (Korea)
        "kauth.kakao.com",
        "accounts.kakao.com",

        // Naver (Korea)
        "nid.naver.com",

        // Daum (Korea)
        "accounts.kakao.com",

        // Xero (Accounting)
        "login.xero.com",

        // Shopify
        "accounts.shopify.com",

        // QuickBooks / Intuit
        "appcenter.intuit.com",

        // Stripe Connect
        "connect.stripe.com",

        // DocuSign
        "account.docusign.com",

        // Hubspot
        "app.hubspot.com",

        // Mailchimp
        "login.mailchimp.com",

        // Zendesk
        "www.zendesk.com",

        // Freshworks
        "accounts.freshworks.com",

        // Intercom
        "app.intercom.com",

        // Asana
        "app.asana.com",

        // Monday.com
        "auth.monday.com",

        // Trello
        "trello.com",

        // Basecamp
        "launchpad.37signals.com",

        // Linear
        "linear.app",

        // Supabase
        "api.supabase.com",

        // Firebase
        "accounts.firebase.google.com",

        // AWS Cognito
        "cognito-idp.amazonaws.com",

        // Keycloak instances (common pattern)
        "sso.redhat.com",

        // France Connect (French government SSO)
        "app.franceconnect.gouv.fr",
        "fcp.integ01.dev-franceconnect.fr",

        // Gov.uk (UK government)
        "signin.account.gov.uk",
        "www.gov.uk",

        // ID.me (US verification)
        "api.id.me",
        "secure.id.me",

        // BankID (Sweden/Norway)
        "appapi2.bankid.com",
        "www.bankid.com",

        // NemID / MitID (Denmark)
        "www.nemid.nu",
        "www.mitid.dk",

        // Verimi (Germany)
        "verimi.de",
        "web.verimi.de",

        // itsme (Belgium)
        "www.itsme-id.com",
        "itsme-id.com",

        // SPID (Italy)
        "identity.infocert.it",
        "idp.namirialtsp.com",
        "identity.sieltecloud.it",
        "spid.poste.it",
        "login.id.tim.it",
        "spid.register.it",
        "id.lepida.it",

        // Cl@ve (Spain)
        "clave.gob.es",
        "pasarela.clave.gob.es",
    ]

    /// OAuth domain suffixes for identity providers.
    private static let oauthDomainSuffixes: Set<String> = [
        // Enterprise identity providers
        ".okta.com",
        ".oktapreview.com",
        ".auth0.com",
        ".onelogin.com",
        ".duosecurity.com",
        ".duo.com",
        ".ping-eng.com",
        ".pingidentity.com",
        ".forgerock.com",
        ".cyberark.com",
        ".sailpoint.com",
        ".jumpcloud.com",
        ".secureauth.com",
        ".centrify.com",
        ".identityserver.io",

        // Cloud providers
        ".awsapps.com",
        ".amazonaws.com",
        ".azure.com",
        ".azuread.com",
        ".b2clogin.com", // Azure AD B2C
        ".googleusercontent.com",

        // Firebase / Supabase
        ".firebaseapp.com",
        ".supabase.co",

        // Keycloak / OIDC providers
        ".keycloak.org",

        // WorkOS
        ".workos.com",

        // Clerk
        ".clerk.dev",
        ".clerk.accounts.dev",

        // Stytch
        ".stytch.com",

        // Magic.link
        ".magic.link",

        // Descope
        ".descope.com",

        // FusionAuth
        ".fusionauth.io",

        // Ory
        ".ory.sh",
        ".ory.dev",

        // Gluu
        ".gluu.org",

        // WSO2
        ".wso2.com",

        // Generic SSO patterns
        ".sso.com",
        ".login.com",
        ".accounts.com",
    ]

    /// OAuth path patterns by domain.
    private static let oauthPathPatterns: [String: [String]] = [
        "google.com": [
            "/o/oauth2/auth",
            "/o/oauth2/v2/auth",
            "/signin/oauth",
            "/accounts/signin",
        ],
        "facebook.com": [
            "/dialog/oauth",
            "/v\\d+/dialog/oauth",
            "/login.php",
        ],
        "github.com": [
            "/login/oauth/authorize",
            "/login/oauth/access_token",
        ],
        "twitter.com": [
            "/oauth/authenticate",
            "/oauth/authorize",
            "/i/oauth2/authorize",
        ],
        "x.com": [
            "/i/oauth2/authorize",
        ],
        "linkedin.com": [
            "/oauth/v2/authorization",
        ],
        "amazon.com": [
            "/ap/oa",
            "/ap/signin",
        ],
        "microsoft.com": [
            "/common/oauth2/authorize",
            "/common/oauth2/v2.0/authorize",
        ],
        "apple.com": [
            "/auth/authorize",
        ],
        "atlassian.com": [
            "/authorize",
            "/oauth/authorize",
        ],
        "discord.com": [
            "/api/oauth2/authorize",
            "/oauth2/authorize",
        ],
        "spotify.com": [
            "/authorize",
        ],
        "twitch.tv": [
            "/oauth2/authorize",
        ],
        "reddit.com": [
            "/api/v1/authorize",
        ],
        "dropbox.com": [
            "/oauth2/authorize",
        ],
        "slack.com": [
            "/oauth/v2/authorize",
            "/oauth/authorize",
        ],
        "zoom.us": [
            "/oauth/authorize",
        ],
        "gitlab.com": [
            "/oauth/authorize",
        ],
        "bitbucket.org": [
            "/site/oauth2/authorize",
        ],
        "yandex.com": [
            "/authorize",
        ],
        "yandex.ru": [
            "/authorize",
        ],
        "vk.com": [
            "/authorize",
        ],
        "baidu.com": [
            "/oauth/2.0/authorize",
        ],
        "weibo.com": [
            "/oauth2/authorize",
        ],
        "qq.com": [
            "/oauth2.0/authorize",
        ],
        "line.me": [
            "/oauth2/v2.1/authorize",
        ],
        "kakao.com": [
            "/oauth/authorize",
        ],
        "naver.com": [
            "/oauth2.0/authorize",
        ],
        "shopify.com": [
            "/admin/oauth/authorize",
        ],
        "intuit.com": [
            "/connect/oauth2",
        ],
    ]

    /// Generic OAuth indicators in query strings.
    private static let genericOAuthIndicators: Set<String> = [
        "response_type=code",
        "response_type=token",
        "grant_type=authorization_code",
        "client_id=",
        "redirect_uri=",
        "oauth_token=",
        "oauth_verifier=",
    ]
}

// MARK: - OAuth Provider

/// Known OAuth providers with their associated domains.
enum OAuthProvider: String, CaseIterable, Sendable {
    // Major US providers
    case google
    case microsoft
    case apple
    case facebook
    case github
    case twitter
    case linkedin
    case amazon
    case yahoo

    // Developer/Enterprise
    case atlassian
    case okta
    case auth0
    case salesforce

    // Social/Entertainment
    case discord
    case spotify
    case twitch
    case reddit
    case pinterest
    case snapchat
    case tiktok

    // Productivity
    case slack
    case zoom
    case notion
    case figma
    case dropbox
    case adobe

    // Russian providers
    case yandex
    case vk
    case mailru

    // Chinese providers
    case baidu
    case weibo
    case wechat
    case qq

    // Asian providers
    case line
    case kakao
    case naver
    case rakuten

    /// Domains associated with this provider.
    var domains: [String] {
        switch self {
        case .google:
            ["google.com", "googleapis.com", "youtube.com"]
        case .microsoft:
            ["microsoft.com", "microsoftonline.com", "live.com", "office.com", "azure.com"]
        case .apple:
            ["apple.com", "icloud.com"]
        case .facebook:
            ["facebook.com", "fb.com", "instagram.com", "meta.com"]
        case .github:
            ["github.com", "githubusercontent.com"]
        case .twitter:
            ["twitter.com", "x.com"]
        case .linkedin:
            ["linkedin.com"]
        case .amazon:
            [
                "amazon.com", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.es",
                "amazon.it", "amazon.nl", "amazon.co.jp", "amazon.ca", "amazon.com.au",
                "amazon.in", "amazon.com.br", "amazon.com.mx", "amazon.sg", "amazon.ae",
                "amazon.sa", "amazon.pl", "amazon.se", "amazon.com.tr",
            ]
        case .yahoo:
            ["yahoo.com", "yahoo.co.jp", "aol.com"]
        case .atlassian:
            ["atlassian.com", "atlassian.net"]
        case .okta:
            ["okta.com", "oktapreview.com"]
        case .auth0:
            ["auth0.com"]
        case .salesforce:
            ["salesforce.com", "force.com"]
        case .discord:
            ["discord.com", "discordapp.com"]
        case .spotify:
            ["spotify.com"]
        case .twitch:
            ["twitch.tv"]
        case .reddit:
            ["reddit.com"]
        case .pinterest:
            ["pinterest.com"]
        case .snapchat:
            ["snapchat.com"]
        case .tiktok:
            ["tiktok.com"]
        case .slack:
            ["slack.com"]
        case .zoom:
            ["zoom.us"]
        case .notion:
            ["notion.so", "notion.com"]
        case .figma:
            ["figma.com"]
        case .dropbox:
            ["dropbox.com"]
        case .adobe:
            ["adobe.com", "adobelogin.com"]
        case .yandex:
            ["yandex.com", "yandex.ru"]
        case .vk:
            ["vk.com"]
        case .mailru:
            ["mail.ru"]
        case .baidu:
            ["baidu.com"]
        case .weibo:
            ["weibo.com"]
        case .wechat:
            ["weixin.qq.com", "wechat.com"]
        case .qq:
            ["qq.com"]
        case .line:
            ["line.me"]
        case .kakao:
            ["kakao.com"]
        case .naver:
            ["naver.com"]
        case .rakuten:
            ["rakuten.co.jp"]
        }
    }

    /// Display name for this provider.
    var displayName: String {
        switch self {
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .apple: "Apple"
        case .facebook: "Meta (Facebook)"
        case .github: "GitHub"
        case .twitter: "X (Twitter)"
        case .linkedin: "LinkedIn"
        case .amazon: "Amazon"
        case .yahoo: "Yahoo"
        case .atlassian: "Atlassian"
        case .okta: "Okta"
        case .auth0: "Auth0"
        case .salesforce: "Salesforce"
        case .discord: "Discord"
        case .spotify: "Spotify"
        case .twitch: "Twitch"
        case .reddit: "Reddit"
        case .pinterest: "Pinterest"
        case .snapchat: "Snapchat"
        case .tiktok: "TikTok"
        case .slack: "Slack"
        case .zoom: "Zoom"
        case .notion: "Notion"
        case .figma: "Figma"
        case .dropbox: "Dropbox"
        case .adobe: "Adobe"
        case .yandex: "Яндекс (Yandex)"
        case .vk: "ВКонтакте (VK)"
        case .mailru: "Mail.ru"
        case .baidu: "百度 (Baidu)"
        case .weibo: "微博 (Weibo)"
        case .wechat: "微信 (WeChat)"
        case .qq: "QQ"
        case .line: "LINE"
        case .kakao: "카카오 (Kakao)"
        case .naver: "네이버 (Naver)"
        case .rakuten: "楽天 (Rakuten)"
        }
    }
}
