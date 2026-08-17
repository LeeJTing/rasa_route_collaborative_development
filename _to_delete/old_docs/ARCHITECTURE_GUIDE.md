# Rasa Route — Developer Guide

How the project is laid out, and the rules for adding to it.

**What this scaffold is.** Structure, theme, routing, config and wiring — complete and working. Screens, business logic and data access — deliberately empty. Every class in `model/business_logic/` and `model/repositories/` is a **class name, a constructor and its injected dependencies, and nothing else**: no methods, no bodies, no placeholder returns. The shape of the architecture is there; every behaviour is yours to add.

**One new dependency:** `provider`, used only to connect each View to its ViewModel.

Sources this scaffold was built from:

- `Software Architecture Diagram` (project docs) — the layer structure
- [Figma mock-up](https://www.figma.com/design/oOcjCvoyodV4qdNvOW2dlg/Colloborative-Development-Mock-up) — all colours, typography and sizing
- Live Supabase schema (`odtmtukexckfjbuqkxyo`) — every data model field
- `Supabase ERD Check Report` — the known schema gaps

---

## 1. First run

```bash
flutter pub get
flutter analyze
flutter run
```

The app starts and every screen renders a placeholder. That is expected — the plumbing is what's built.

---

## 2. Folder map

```
lib/
├── main.dart                     entry point: Env → Supabase → Wiring → runApp
├── app/                          composition root
│   ├── app.dart                  RasaRouteApp: theme + the route table
│   ├── wiring.dart               Wiring class. All `new` lives here.
│   ├── config/env.dart           typed .env access
│   ├── routing/
│   │   ├── app_routes.dart       route-name String constants
│   │   └── app_navigator.dart    context-free navigation for ViewModels
│   └── theme/
│       ├── app_colors.dart       every colour
│       ├── app_text_styles.dart  every text style
│       ├── app_dimensions.dart   AppSpacing / AppRadius / AppSizes
│       └── app_theme.dart        assembles ThemeData + component themes
│
├── core/                         cross-cutting contracts
│   ├── base_view_model.dart      BaseViewModel: state + runGuarded
│   ├── view_state.dart           idle | busy | ready | error
│   └── json_model.dart           JsonModel + JsonReader parsing helpers
│
├── views/                        PRESENTATION — one folder per screen
│   └── <screen>_view/
│       ├── <screen>_view.dart    StatefulWidget — placeholder body
│       └── widgets/              reusable pieces of THIS screen only
│
├── view_models/                  PRESENTATION — one ChangeNotifier per screen
│   ├── <screen>_view_model.dart
│   ├── current_location_facade.dart    ← inbound facade (background → ViewModel)
│   └── update_restaurant_facade.dart   ← inbound facade
│
├── domain_model/                 what the app reasons about (rich, serialisable)
│
├── model/                        BUSINESS + DATA
│   ├── business_logic/           logic classes + 4 logic facades
│   ├── repositories/             repositories + 4 repository facades
│   ├── data_models/              1:1 with Supabase tables
│   └── background_process/       LocationMonitor, RestaurantMonitor
│
├── shared_client/                APIManager, LocalStorageManager, DeviceCapabilityManager
└── external/                     SupabaseService, GeminiService — the only SDK imports
```

### The one-way dependency rule

```
View  →  ViewModel  →  Logic Facade  →  Logic  →  Repository Facade  →  Repository
                                                                            ↓
                                                     APIManager / LocalStorageManager
                                                                            ↓
                                                     SupabaseService / GeminiService
```

Arrows point one way only. Concretely:

| Layer         | May import                                                | Must never import                                             |
| ------------- | --------------------------------------------------------- | ------------------------------------------------------------- |
| View          | its ViewModel, theme, its own widgets, `AppRoutes`        | repositories, logic, Supabase, Gemini                         |
| ViewModel     | **one** logic facade (two if unavoidable), domain models  | `package:flutter/material.dart`, `BuildContext`, repositories |
| Logic         | **one** repository facade, domain models                  | Flutter, `APIManager`, Supabase, Gemini                       |
| Repository    | `APIManager`, `LocalStorageManager`, data + domain models | Flutter, ViewModels                                           |
| Shared client | external services                                         | anything above it                                             |

If you find yourself importing "upward", the design is wrong — not the rule.

---

## 3. Theme and colours — done, use it

**Never write `Color(0xFF...)` or a bare number outside `lib/app/theme/`.**

```dart
// Best — the theme already knows.
Text('Nasi Lemak', style: Theme.of(context).textTheme.titleMedium)
Container(color: Theme.of(context).colorScheme.primary)

// Fine — when there is no theme slot for it.
Padding(padding: const EdgeInsets.all(AppSpacing.lg))
Container(decoration: const BoxDecoration(color: AppColors.surfaceVariant))

// Wrong.
Text('Nasi Lemak', style: TextStyle(fontSize: 16, color: Color(0xFF2B2B2B)))
Padding(padding: const EdgeInsets.all(16))
```

Colours (`AppColors`) — `[Figma]` values come straight from the mock-up, `[Derived]` are computed states:

| Token               | Value                 | Used for                             |
| ------------------- | --------------------- | ------------------------------------ |
| `primary`           | `#FF9700`             | CTAs, active nav item, camera button |
| `primaryDark`       | `#E07E00`             | pressed state                        |
| `primaryContainer`  | `#FFE3BF`             | selected chips, highlighted rows     |
| `secondary`         | `#F0B400`             | ratings, badges                      |
| `background`        | `#FFF8E7`             | scaffold                             |
| `surface`           | `#FFFFFF`             | cards, sheets                        |
| `surfaceVariant`    | `#FFEDBE`             | bottom nav band                      |
| `outline`           | `#E8DCBB`             | dividers, input borders              |
| `textPrimary`       | `#2B2B2B`             | body and headings                    |
| `textSecondary`     | `#7F91A8`             | muted text, inactive icons           |
| `error` / `success` | `#D64545` / `#3FA34D` | status                               |

Spacing (`AppSpacing`), 4pt scale: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`, plus `screenPadding` and `cardPadding`.
Radii (`AppRadius`): `sm 8 · md 12 · lg 16 · xl 24 · pill`, plus `cardRadius`, `buttonRadius`, `sheetRadius`.
Sizes (`AppSizes`): `bottomNavHeight 74`, `navFabDiameter 58`, `navIconSize 25`, `buttonHeight 52`, `minTapTarget 48`, avatars.

Typography is Roboto, mapped onto Material 3 `TextTheme` slots. `AppTextStyles.labelMediumSelected` is the one style with no slot — the active bottom-nav label.

`AppTheme` also carries component themes for buttons, inputs, cards, chips, dividers, sheets and snackbars. Add one there rather than decorating at a call site.

> Figma's MCP hit its Starter-plan rate limit during setup, so tokens were derived from the values already in the codebase (which came from the mock-up). Re-run `get_variable_defs` when access is back and reconcile.

---

## 4. Configuration (`.env`)

`.env` is git-ignored; `.env.example` is committed and lists every key.

`Env.load()` runs first in `main()` and fills an internal map; every getter reads from that map with a documented fallback. The file read itself is not implemented — the scaffold has no config package. When you add one, only `Env.load` changes; every call site already goes through the getters.

Adding a key means editing three places:

1. `.env.example` — document it
2. `.env` — your local value
3. `lib/app/config/env.dart` — a key constant and a typed getter

Nothing outside `Env` reads configuration.

```dart
Env.supabaseUrl
Env.geminiModel           // falls back to 'gemini-2.5-flash'
Env.apiTimeout            // Duration
Env.locationPollInterval  // Duration, drives LocationMonitor
Env.isProduction
```

**The publishable/anon key only.** Never put a service-role key in `.env` — it ships inside the app bundle.

---

## 5. Routing (Navigator 1.0, named routes) — done, use it

Two pieces:

- `lib/app/routing/app_routes.dart` — the route names, as plain `String` constants
- `MaterialApp(routes: ...)` in `lib/app/app.dart` — the route table itself, a
  `Map<String, WidgetBuilder>` written out in full

There is no `onGenerateRoute` and no argument classes. Every route builds a
const View with no parameters, so navigating is just a name:

```dart
Navigator.pushNamed(context, AppRoutes.profile);

Navigator.pushReplacementNamed(context, AppRoutes.mainShell);   // login → shell

Navigator.pushNamedAndRemoveUntil(                              // logout
  context, AppRoutes.loginRegister, (_) => false,
);
```

Never type `'/food-detail'` at a call site. A wrong constant is a compile error;
a wrong string is a runtime crash.

### Passing data to a screen

Screens that need an id (`FoodDetailView`, `RestaurantDetailView`,
`LandmarkDetailView`, `OtpView`, …) declare it as a plain mutable field on their
ViewModel with a default, not as a constructor argument:

```dart
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel({required FoodLogicFacade foodFacade, ...});

  /// Which dish to show. Set by the caller after construction.
  int localFoodId = 0;
}
```

Set it before `onInit()` runs, or set it and call `refresh()`. When the team
decides how ids should travel between screens — `settings.arguments`, a shared
selection object, deep links — that decision lands in one place per screen
rather than being spread through a router.

### Adding a screen

1. `AppRoutes` — add the constant.
2. `MaterialApp(routes: ...)` in `app.dart` — add the entry.
3. Create `lib/views/<name>_view/` with `widgets/`, and
   `lib/view_models/<name>_view_model.dart`.

### Navigating from a ViewModel

ViewModels have no `BuildContext`. Two options:

- **Return a decision** (preferred): the command returns `bool`/an id, the View
  performs the push.
- **Use `AppNavigator`** (`context.read<AppNavigator>()`) when the
  decision is genuinely business logic. It owns `MaterialApp.navigatorKey` and
  exposes `push` / `replaceWith` / `resetTo` / `pop` without a context.

---

## 6. Provider: wiring a View to a ViewModel

This is the part that is fully built. Every one of the 18 screens follows it.

### There is no `AppDependencies` singleton

The object graph lives in `Wiring`, and is published to the widget tree via
`MultiProvider` in `main.dart`. A View reaches for exactly what it needs
using `context.read<T>()`. Read a screen file and you can see its full
dependency list without looking anywhere else.

```dart
context.read<TouristInformationLogicFacade>()
context.read<FoodLogicFacade>()
context.read<DiscoveryLogicFacade>()
context.read<LandmarkLogicFacade>()
context.read<CurrentLocationFacade>()   // inbound: background → ViewModel
context.read<UpdateRestaurantFacade>()  // inbound: background → ViewModel
context.read<AppNavigator>()
```

**ViewModels are deliberately not registered globally.** Each View creates its
own in `initState`, so it is disposed with the screen. Keeping 18 ChangeNotifiers
alive at the root for the whole session would be the opposite of what we want.

### The pattern — every View looks like this

```dart
class LocalFoodListView extends StatefulWidget {
  const LocalFoodListView({super.key});
  @override
  State<LocalFoodListView> createState() => _LocalFoodListViewState();
}

class _LocalFoodListViewState extends State<LocalFoodListView> {
  late final LocalFoodListViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    // The View states its own dependencies, right here.
    _viewModel = LocalFoodListViewModel(
      foodFacade: context.read<FoodLogicFacade>(),
    );
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();   // always. The ViewModel is yours to kill.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LocalFoodListViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: AppBar(title: const Text('Learn')),
        body: SafeArea(
          child: Consumer<LocalFoodListViewModel>(
            builder: (context, viewModel, _) {
              // ← your layout goes here, driven by `viewModel`
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
```

`ChangeNotifierProvider.value` (not `create:`) — the State owns the lifetime, so
Provider must not dispose it too.

Provider is used purely to get the ViewModel down to the widgets inside one
screen. It is not the app's dependency-injection mechanism; `AppDependencies`
is.

### Reading in a widget

| Call                 | When                                            |
| -------------------- | ----------------------------------------------- |
| `context.watch<T>()` | in `build` — rebuilds this widget on notify     |
| `Consumer<T>`        | in `build` — rebuilds only the subtree, cheaper |
| `Selector<T, R>`     | when you want to rebuild on one field only      |
| `context.read<T>()`  | inside callbacks — does **not** rebuild         |

Never `context.watch` outside `build`. Never `context.read` in `build`. Note
that `context.read` is now used in `initState` — the ViewModel gets its
facades from the tree, not from a singleton.

### Writing a ViewModel

```dart
class LocalFoodListViewModel extends BaseViewModel {
  LocalFoodListViewModel({required FoodLogicFacade foodFacade})
    : _food = foodFacade;

  final FoodLogicFacade _food;             // interface, injected

  List<LocalFood> _foods = const [];       // private state
  List<LocalFood> get foods => _foods;     // read-only getter

  bool get isEmpty => _foods.isEmpty;

  @override
  Future<void> onInit() => refresh();

  Future<void> refresh() => runGuarded(() async {
    _foods = await _food.browse();
  });
}
```

`runGuarded` sets `busy` → runs → sets `ready`, or catches and sets `error`.
Pass `silent: true` for background refreshes that shouldn't flash a spinner.
Never call `notifyListeners()` directly — use `safeNotifyListeners()`, which
tolerates an async task finishing after the screen is gone.

`LocalFoodListViewModel` is worth reading as a reference: it also shows
debounced search and an optimistic favourite toggle that reverts on failure.

### `widgets/` folders

Each screen has `lib/views/<screen>_view/widgets/` for pieces used **only by
that screen**. A widget in there must:

- take data and callbacks through its constructor — never `context.read` a
  ViewModel;
- hold no business logic;
- style from the theme.

The moment a second screen needs it, move it to a shared
`lib/views/common_widgets/` folder.

---

## 7. Facades — three kinds, don't mix them up

### 7a. Logic facade — ViewModel calls one object, it fans out to many logic classes

`lib/model/business_logic/*_logic_facade.dart`

| Facade                          | Fans out to                                                              | Used by                                                                            |
| ------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| `TouristInformationLogicFacade` | `AuthenticateLogic`, `UserProfileLogic`                                  | LoginRegister, Otp, ProfileSetUp, Profile                                          |
| `FoodLogicFacade`               | `FoodKnowledgeLogic`, `FoodComparisonLogic`, `FoodRecommendationLogic`   | LocalFoodList, FoodDetail, FoodComparison, FoodRecommendation, FavouriteCollection |
| `DiscoveryLogicFacade`          | `RestaurantDiscoveryLogic`, `FoodDiscoveryLogic`, `FoodRecognitionLogic` | RestaurantRecommendation, RestaurantDetail, RestaurantItemList, FoodRecognition    |
| `LandmarkLogicFacade`           | `LandmarkSubmissionLogic`, `MapExplorationLogic`                         | AddLandmark, LandmarkHistory, LandmarkDetail, Dashboard                            |

Rules: a facade contains **no business rules** — it forwards, and at most composes two calls into one screen-shaped operation.

Right now each facade is just a constructor holding its logic classes. When you add a method to a logic class, add the one-line forwarder here so the ViewModel keeps talking to a single object.

### 7b. Repository facade — logic calls one object, it fans out to many repositories

`lib/model/repositories/*_repository_facade.dart`

| Facade                      | Fans out to                                                              |
| --------------------------- | ------------------------------------------------------------------------ |
| `TouristRepositoryFacade`   | `AuthRepository`, `TouristProfileRepository`, `InteractionRepository`    |
| `FoodRepositoryFacade`      | `FoodKnowledgeRepository`, `RecommendationRepository`, `SwipeRepository` |
| `DiscoveryRepositoryFacade` | `RestaurantRepository`, `RecognitionRepository`                          |
| `LandmarkRepositoryFacade`  | `SubmittedLandmarkRepository`, `MapRepository`, `LocationRepository`     |

Same rules, one level down. A logic class holds **one** repository facade. (`FoodRecognitionLogic` holds two — it recognises through one and resolves the label against the catalogue through another. That's the documented exception, not a licence.)

When you add a repository, add it to exactly one facade.

### 7c. Inbound ViewModel facade — background process calls one object, it fans out to many ViewModels

`lib/view_models/current_location_facade.dart`, `lib/view_models/update_restaurant_facade.dart`

The mirror image of the other two. A background process must not hold ViewModel references, so it publishes to one facade and any number of ViewModels register as listeners:

```dart
class DashboardViewModel extends BaseViewModel
    implements CurrentLocationListener {

  @override
  Future<void> onInit() {
    _locationFacade.register(this);        // register in onInit
    return refresh();
  }

  @override
  void onCurrentLocationChanged(LocationDataModel location) {
    _location = location;
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _locationFacade.unregister(this);      // ALWAYS unregister
    super.dispose();
  }
}

// LocationMonitor never knows DashboardViewModel exists.
_facade.publish(newFix);
```

Rules:

- register in `onInit`, unregister in `dispose` — forgetting the second leaks the ViewModel;
- listener callbacks must be cheap and must not throw (the facade swallows errors so one bad listener can't kill the monitor);
- a late-registering ViewModel is immediately given the last published value, so screens are never blank.

### Background processes

`LocationMonitor` and `RestaurantMonitor` read **down** through a logic facade exactly like a ViewModel does, and write **up** through an inbound facade. No Flutter imports, no UI state. Started from `main()` after the first frame via `AppDependencies.startBackgroundProcesses()`.

`RestaurantMonitor` is both: it listens on `CurrentLocationFacade` and publishes on `UpdateRestaurantFacade`. Its start/stop/timer/de-duplication wiring is real; only the query behind it is empty.

---

## 8. Models — every one has `toJson` / `fromJson`

These are fully implemented.

**Data models** (`lib/model/data_models/`) mirror Supabase tables 1:1 — same column names snake_cased in JSON, same nullability, no computed values, no behaviour. Comma-separated text stays comma-separated text.

**Domain models** (`lib/domain_model/`) are what the app reasons about — lists instead of CSV, enums instead of free text, computed getters like `LocalFood.satisfies(restrictions)` and `Restaurant.distanceLabel`.

Both implement `JsonModel`. The conversion between them belongs in **repositories only** — never in a ViewModel, never in a View.

```dart
class LocalFoodDataModel implements JsonModel {
  const LocalFoodDataModel({required this.localFoodId, required this.foodName});

  final int localFoodId;
  final String? description;

  factory LocalFoodDataModel.fromJson(Map<String, dynamic> json) {
    return LocalFoodDataModel(
      localFoodId: JsonReader.asInt(json['local_food_id']),
      description: JsonReader.asStringOrNull(json['description']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'local_food_id': localFoodId,
    'description': description,
  };
}
```

Always parse through `JsonReader` (`lib/core/json_model.dart`). Supabase returns `numeric` as `String` on some drivers, `time` as `"HH:MM:SS"`, and `null` for every nullable column — `JsonReader` absorbs that so `fromJson` stays one line per field. `JsonReader.asModelList` handles nested arrays; `JsonReader.asEnum` handles enums.

Use `.compact()` on a `toJson()` result before a partial Supabase update, so nulls don't overwrite existing columns.

Round-trip is the test: `fromJson(x.toJson()).toJson() == x.toJson()`.

**Naming note:** `domain_model/map.dart` declares **`ExplorationMap`**, not `Map` — `Map` is a `dart:core` type and would shadow it in every importing file. The filename follows the architecture diagram; the class name doesn't.

---

## 9. What's empty, and what filling it in looks like

Empty — class name, constructor and injected dependencies only, no methods at all:

- all 11 **repositories** and 4 **repository facades** in `model/repositories/`
- all 10 **logic classes** and 4 **logic facades** in `model/business_logic/`
- both **background processes** in `model/background_process/`
- all 18 **ViewModels** (constructor + facade fields; the three that listen to a
  background process also have their register / callback / unregister wiring)
- every **View** body and every widget in a `widgets/` folder
- `SupabaseService`, `GeminiService`, `LocalStorageManager` (in-memory),
  `StubDeviceCapabilityManager`, `Env.load`

Real and working: theme, the route table, `Wiring`, `BaseViewModel`,
`JsonReader`, all data and domain models, the inbound ViewModel facades, and
the bottom-nav shell.

### Filling in one vertical slice

Take the dish list. Every step adds code to exactly one layer; nothing above or
below has to change shape.

1. **`FoodKnowledgeRepository`** — add
   `Future<List<LocalFood>> fetchAll()`. Inside, call
   `api.selectAll(APIManager.tableLocalFood, columns: '*, local_food_image(img_name)')`,
   map rows through `LocalFoodDataModel.fromJson`, convert to `LocalFood`, and
   cache with `storage.writeJsonList(...)`.

2. **`FoodRepositoryFacade`** — add a one-line forwarder:
   `Future<List<LocalFood>> allFoods() => knowledge.fetchAll();`

3. **`FoodKnowledgeLogic`** — add `browse()`, calling `repository.allFoods()`
   plus whatever rule belongs at this layer (filtering by dietary restriction,
   sorting, and so on).

4. **`FoodLogicFacade`** — add `Future<List<LocalFood>> browse() => knowledge.browse();`

5. **`LocalFoodListViewModel`** — add the state and the command:
   
   ```dart
   List<LocalFood> _foods = const <LocalFood>[];
   List<LocalFood> get foods => _foods;
   
   @override
   Future<void> onInit() => refresh();
   
   Future<void> refresh() => runGuarded(() async {
     _foods = await foodFacade.browse();
   });
   ```

6. **`LocalFoodListView`** — build the list from `viewModel.foods` inside the
   existing `Consumer`.

The two facade steps are one line each. That is the cost of the layering, and
what you get back is that step 1 can change completely — different table,
different cache strategy, a different backend — without steps 3 to 6 knowing.

---

## 10. Known gaps carried over from the ERD check

| Gap                                                                                          | Why it matters                                                                                                         |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| RLS enabled with zero policies                                                               | **Every** select returns `[]` and every write is denied. Apply the RLS migration first or nothing will appear to work. |
| No `tourist` row created on sign-up                                                          | Every `tourist_id` FK fails after registration.                                                                        |
| No `interaction`, `swipe_session`, `food_pairing`, `food_similarity` tables                  | Those repositories have nowhere to write.                                                                              |
| No `restaurant.is_halal`                                                                     | `RestaurantDiscoveryLogic.nearby` accepts `restrictions` but can't apply them.                                         |
| `submitted_landmark.landmark_id` / `opening_hours.opening_hours_id` have no identity default | Inserts must supply the id by hand.                                                                                    |
| No PostGIS                                                                                   | Nearby search has to filter client-side.                                                                               |
| No RPCs                                                                                      | Heat-map aggregation has nothing to call.                                                                              |

## 11. Other things you'll notice

- **`lib/views/opt_view/`** is a typo for `otp_view` inherited from the original tree. The file and class inside are correctly named `otp_view.dart` / `OtpView`. Rename the folder when convenient — it's a one-line change in `app.dart`.
- **`StubDeviceCapabilityManager`** returns "permission denied" for everything. Replace it with a real implementation and swap it in `AppDependencies.build()` — one line, and it's injectable so tests can pass a fake.
- **Views are all `StatefulWidget`s**, as agreed, even where the screen looks stateless. The State object is what owns the ViewModel's lifetime.

---

## 12. Checklist for a new feature

- [ ] Data model added for any new table, with `toJson`/`fromJson` via `JsonReader`
- [ ] Domain model added if the app needs a richer shape
- [ ] Repository owns one concern, decides local vs remote itself
- [ ] Repository added to exactly one repository facade
- [ ] Logic class holds one repository facade, contains the rules, has no Flutter imports
- [ ] Logic class added to exactly one logic facade
- [ ] ViewModel extends `BaseViewModel`, holds one logic facade, uses `runGuarded`, no `BuildContext`
- [ ] View is a `StatefulWidget`, builds its ViewModel in `initState` from `context.read<T>()`, disposes it, wraps it in its own `ChangeNotifierProvider.value`
- [ ] Reusable pieces in the screen's `widgets/` folder, driven by constructor params
- [ ] Route constant in `AppRoutes` + entry in `MaterialApp(routes: ...)`
- [ ] No raw hex colours, no magic numbers, no route string literals, no config read outside `Env`
- [ ] Constructed in `Wiring.buildProviders()` if it's a singleton
- [ ] `flutter analyse` clean
