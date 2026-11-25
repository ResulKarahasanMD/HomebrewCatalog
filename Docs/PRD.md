# Homebrew Catalog - Product Requirements Document (PRD)

## 1. Product Requirements and Scope

### 1.1 Objective
To create a native, free macOS utility application that serves as a clean, user-friendly "App Store" for the Homebrew Catalog. It allows casual users to discover, search, and learn about macOS applications and command-line tools available via Homebrew Cask and Formula.

### 1.2 MVP Features (Must-Have)
- **Discover & Browse:** A "Featured" landing page showcasing the most popular and recently updated Casks and Formulae. Category-based browsing (e.g., Developer Tools, Productivity, Multimedia).
- **Unified Search:** A global, real-time search bar to find Casks and Formulae by name, description, or keywords.
- **Rich Detail Views:** A dedicated detail screen for every item displaying:
  - Name, Description, Version, License.
  - Official Website link.
  - The exact Terminal command to install (`brew install` or `brew install --cask`).
- **Favorites & History:** Users can mark items as favorites and view a history of recently viewed items.
- **Cross-Reference:** Show related items or dependencies (e.g., showing the underlying Formula for a Cask).

### 1.3 Post-MVP / Nice-to-Have Features
- **Analytics & Trends:** Integrate Homebrew analytics to display 30d/90d/1y installation graphs.
- **Dependency Visualizer:** A visual map showing the dependency tree for a Formula.
- **Tap Manager:** Browsing and adding third-party Homebrew Taps.
- **Update Notifications:** A section showing which locally installed Casks/Formulae have available updates (requires local brew access, which is a sandbox violation; likely out of scope for App Store).
- **Icon Fetching:** Attempting to fetch application icons from their homepage or a local mapping database.

## 2. Technical Architecture and Data Management

### 2.1 Technology Stack
- **Platform:** macOS 15.0+ (Sequoia)
- **Language:** Swift 6.3.1
- **UI Framework:** SwiftUI (native macOS lifecycle)
- **State Management:** Observation framework (using the `@Observable` macro)
- **Persistence:** SwiftData (for caching metadata, favorites, and history)
- **Networking:** URLSession + Codable / JSONDecoder
- **Build Tool:** Xcode 26.4.1

### 2.2 Data Sources & API Integration
The app will consume the official Homebrew Formulae JSON API:
- **All Formulae:** `https://formulae.brew.sh/api/formula.json`
- **All Casks:** `https://formulae.brew.sh/api/cask.json`
- **Detail Endpoints:** `https://formulae.brew.sh/api/formula/{name}.json` / `api/cask/{name}.json`
- **Analytics:** `https://formulae.brew.sh/api/analytics/...`

**Strategy:**
1. **Background Download:** Fetch the dump on first launch or update.
2. **Parsing:** Parse JSON in a background thread via `actor HomebrewAPIService`.
3. **Local Database:** Store parsed data in the file system (`CatalogCache`) and persist user data (`FavoriteItem`, `HistoryItem`) in SwiftData.
4. **Differential Updates:** Check for updates periodically (e.g., daily) and re-fetch.

### 2.3 Data Models
- **`BrewItem` (Protocol):** Defines shared fields (id, name, description, homepage, version, license, popularity).
- **`BrewFormula` (Struct):** Extends `BrewItem` + dependencies, conflicts, etc.
- **`BrewCask` (Struct):** Extends `BrewItem` + sha256, app_name, artifacts.
- **`Category` (Enum):** Metadata for grouping with keyword-based heuristic mapping.
- **`FavoriteItem` & `HistoryItem` (SwiftData Entities):** For persisting user-specific data.

### 2.4 State Management Strategy
- **`BrewStore` (`@Observable`):** A single source of truth that owns the entire data layer. It handles loading, searching, filtering, and provides computed properties for the UI.
- **`HomebrewAPIService` (actor):** Handles all network requests asynchronously to prevent UI blocking.
- **`CatalogCache` (actor):** Manages file-system persistence of the raw API data to support offline browsing.
- **`PersistenceController` (MainActor):** Wraps SwiftData logic for favorites and history, providing a clean API for the ViewModels and Views.
