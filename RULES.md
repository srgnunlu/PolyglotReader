# PolyglotReader - Production Rules

## Code Style Rules
- Swift 5.9+ modern syntax kullan
- SwiftLint kurallarına uy (Airbnb Swift Style Guide bazlı)
- Tüm public API'lerde documentation comments zorunlu
- Force unwrap (!) yasak - guard let veya nil coalescing kullan
- implicitlyUnwrappedOptional sadece @IBOutlet'lerde izinli

## Architecture Rules
- MVVM pattern'den sapma yok
- Business logic asla View'larda olmaz - ViewModel veya Service kullan
- Tüm network çağrıları Service katmanından geçer
- @MainActor tüm ViewModel'lerde zorunlu
- Singleton service'ler thread-safe olmalı

## Naming Conventions
- **Types/Classes**: PascalCase (AuthViewModel, PDFService)
- **Functions/Variables**: camelCase (loadDocument, currentUser)
- **Files**: TypeName.swift (PascalCase)
- **Constants**: camelCase veya SCREAMING_SNAKE_CASE for globals
- **Protocols**: -able, -ible, -ing suffix (Loadable, Cacheable)

## Forbidden Practices
- ❌ Force unwrapping (!) - crash riski
- ❌ try! veya try? without proper handling
- ❌ print() statements in production - LoggingService kullan
- ❌ Hardcoded strings for user-facing text
- ❌ Synchronous network calls on main thread
- ❌ Storing sensitive data in UserDefaults
- ❌ API keys in source code

## Required Practices
- ✅ Error handling with do-catch for all throwing functions
- ✅ Weak self in closures to prevent retain cycles
- ✅ Proper cancellation of async tasks
- ✅ Input validation before network calls
- ✅ Rate limiting for API calls
- ✅ Graceful degradation when offline

## Security Requirements
- API keys only in Config.plist (gitignored)
- Keychain for sensitive user data
- Certificate pinning for API calls
- Biometric authentication option
- Secure session token storage

## Performance Requirements
- Images must be downsampled before display
- PDF pages lazy-loaded
- Memory warnings handled
- Background task completion for uploads
- Debounce rapid user inputs

## Testing Requirements
- Unit tests for all Service methods
- UI tests for critical user flows
- Minimum 60% code coverage target
- Mock all external dependencies in tests

## Accessibility Requirements
- VoiceOver labels for all interactive elements
- Dynamic Type support
- Minimum touch target 44x44 points
- Color contrast ratios WCAG AA compliant

## Documentation Requirements
- README.md güncel tutulmalı
- CHANGELOG.md her release için
- Inline documentation for complex logic
- API documentation for all public interfaces

## When in Doubt
- Güvenlik > Performans > Özellik
- Explicit > Implicit
- Readability > Cleverness
- User experience > Technical elegance