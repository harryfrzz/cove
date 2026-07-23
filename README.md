# Cove

Cove is a local-first shelf for screenshots, images, links, and notes. Phase 1 shipped the native iOS 26 vertical slice; Phase 2 replaced the AI mocks with **real on-device models**: Vision OCR, MobileCLIP2 embeddings, hybrid semantic + keyword search, and Foundation Models guided extraction. There are no accounts, cloud calls, analytics, or secrets — **nothing leaves the device at inference time**.

## Requirements

- Xcode 26.3 or newer
- iOS 26 simulator runtime
- Apple Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`)
- An iPhone with a Dynamic Island for the complete demo; use an iPhone 16 Pro simulator

The project’s minimum deployment target is iOS 26.0.

## Project structure

```text
cove/
├── AppIntents/
│   └── CoveQuickCaptureIntent.swift    Action Button shortcut and capture routing
├── Models/
│   ├── CoveStore.swift                 Shared ModelContainer
│   └── ShelfItem.swift                 SwiftData model, Float32 embedding blobs
├── Services/
│   ├── AIServices.swift                Protocols, composition, mock toggle
│   ├── MockAIServices.swift            Phase 1 mocks (fallback demo path)
│   ├── VisionOCRService.swift          Real OCR (RecognizeDocumentsRequest)
│   ├── CLIPTokenizer.swift             CLIP BPE tokenizer (Swift port)
│   ├── MobileCLIPEmbeddingService.swift  Core ML MobileCLIP2-S0, both encoders
│   ├── HybridSearchService.swift       vDSP semantic + keyword RRF fusion
│   ├── FoundationModelsService.swift   Guided generation: classify + extract
│   └── ShelfProcessingPipeline.swift   ShelfProcessor background @ModelActor
├── Resources/AI/                       Local mlpackages + tokenizer assets
├── LiveActivity/
│   ├── CoveProcessingAttributes.swift  Shared ActivityKit state
│   └── ProcessingLiveActivityManager.swift  Snapshot-based activity updates
├── Views/
│   ├── Add/                            Photos, link, and note capture
│   ├── Debug/                          AI Diagnostics harness (DEBUG only)
│   ├── Detail/                         Result, extraction panel, retry, chat
│   ├── Search/                         Hybrid on-device search
│   ├── Shelf/                          Home shelf
│   └── Components/                     Cards and Metal backdrop
├── CoveFlow.metal                      One stitchable shelf-background shader
└── coveApp.swift                       SwiftData, services, launch reconciliation

coveTests/                              Tokenizer/embedding/search/pipeline tests
tools/mobileclip2/                      convert.py + parity_test.py (Python)
coveProcessingWidget/
├── CoveProcessingWidget.swift          Live Activity + Dynamic Island layouts
└── Info.plist
```

`ShelfItem` keeps image bytes in SwiftData external storage. Embeddings are L2-normalized vectors stored as compact `Float32` blobs (`Data`) together with their dimension and a model-version tag; there is intentionally no vector database.

## Real versus mocked (Phase 2)

Real:

- `OCRService` → `VisionOCRService`: Vision `RecognizeDocumentsRequest` (iOS 26, keeps line/table structure) with `RecognizeTextRequest` accurate-level fallback
- `EmbeddingService` → `MobileCLIPEmbeddingService`: MobileCLIP2-S0 image + text encoders as local Core ML models, plus a Swift port of the CLIP BPE tokenizer
- `SearchService` → `HybridSearchService`: vDSP dot-product semantic scan fused with literal keyword matching (reciprocal-rank fusion)
- `SummarizationService` + `StructuredExtractionService` → `FoundationModelsService`: Apple's on-device Foundation Models with `@Generable` guided generation (receipt / event / note schemas), availability-checked on every call
- Background ingestion pipeline (`ShelfProcessor`, a `@ModelActor`): capture → OCR → classify/extract/summarize → embed image → embed enriched text → ready, with per-step persistence, startup reconciliation, and retry
- Everything real from Phase 1 (SwiftUI, SwiftData, Live Activity, App Intents, Metal backdrop)

Still mocked (out of scope this phase):

- `ImageUnderstandingService` (VLM open-ended image Q&A)
- Link metadata fetch, item chat, Calendar, and Reminders actions

### Mock fallback toggle

The full Phase 1 mock stack stays available for a guaranteed demo path:

- Launch argument `--use-mock-ai`, or
- The **AI Diagnostics** debug screen (stethoscope toolbar icon, DEBUG builds) → "Use Phase 1 mocks" toggle (takes effect on next launch).

## On-device models

### MobileCLIP2-S0 (embeddings)

- **Provenance**: [`apple/MobileCLIP2-S0`](https://huggingface.co/apple/MobileCLIP2-S0) checkpoint (license: `apple-amlr`, Apple ML research license — review before shipping commercially). No official Core ML export exists for v2, so `tools/mobileclip2/convert.py` converts both encoders with coremltools 9 via the `torch.export` path (the TorchScript frontend fails on this tower).
- **Chosen variant**: S0 — smallest of the family; on a phone latency beats a marginal accuracy gain.
- **Preprocessing** (verified against open_clip's pretrained registry `_mccfg` and `timm/MobileCLIP2-S0-OpenCLIP`): RGB scaled to `[0,1]` (mean 0, std 1 — **not** the OpenAI CLIP normalization), bilinear shortest-side resize to 256, center crop 256×256. The `[0,1]` scaling is baked into the Core ML image input, so Swift only delivers pixels.
- **Embedding**: 512-d, L2-normalized inside the exported graph and re-normalized defensively in Swift; similarity is a plain dot product. The dimension is read from the compiled model at load time, never hardcoded. Stored embeddings carry `embeddingModelVersion = "mobileclip2-s0-v1"`; launch reconciliation re-embeds items with a stale version.
- **Tokenizer**: exact CLIP BPE (vocab 49408, context 77, SOT 49406 / EOT 49407) reconstructed from the reference merges list; Swift port parity-tested against Python-generated fixtures (`tokenizer-fixtures.json`), including unicode and truncation cases.
- **Parity** (PyTorch fp32 reference vs converted Core ML fp16, 7 fixed images + 8 texts): minimum cosine similarity **0.999792** (image) and **0.999952** (text), all embedding norms within 1±0.001. Text→image retrieval sanity: 4/4 correct pairings with clear margins.
- **Size**: image encoder 22 MB + text encoder 121 MB (fp16) ≈ **143 MB added to the app binary**. The generated model packages are deliberately Git-ignored; create them locally with the workflow below before building the real embedding stack.

To regenerate: create a Python 3.12 venv with `torch==2.7.0 torchvision==0.22.0 open_clip_torch timm coremltools pillow numpy`, download `mobileclip2_s0.pt`, then run `convert.py --checkpoint … --output-dir …` and `parity_test.py` from `tools/mobileclip2/`. Copy the two `.mlpackage`s and both JSON files into `cove/Resources/AI/`.

### Vision OCR

- `RecognizeDocumentsRequest` first (document structure: transcript plus tables re-rendered row-by-row with ` | ` separators for downstream extraction), falling back to `RecognizeTextRequest` with `.accurate` + language correction.
- Recognition languages: English + the device language.
- Images above 2048 px on the longest side are downscaled to 2048 before OCR — below that threshold small receipt text starts dropping out; above it latency grows with no accuracy gain.
- Empty text is a normal result, not an error.

### Foundation Models (summaries + structured extraction)

- Availability is checked on **every** call (`SystemLanguageModel.default.availability`); `deviceNotEligible`, `appleIntelligenceNotEnabled`, and `modelNotReady` all degrade gracefully — the item still gets OCR text and embeddings and becomes searchable, just without a summary.
- Content is classified first (receipt / event / article / note), then routed to a matching `@Generable` schema — typed guided generation, no regex parsing.
- Long OCR text is truncated head (2400 chars) + tail (800 chars) to respect the small context window; receipts carry their signal at the edges.

## Hybrid search

Query embedding is computed once (debounced 250 ms in the search view), then dotted against every stored vector with vDSP — brute force is instant at personal-shelf scale. Two ranked lists are fused with reciprocal-rank fusion (`k = 60`): semantic weight 1.0, keyword weight 1.2. Keyword slightly wins because a literal hit on a merchant name or order number should outrank a loose scene match — CLIP cannot read text inside images, which is exactly the case keyword matching covers. Items with no keyword hit and cosine < 0.18 are dropped (relevance floor). Each item is scored against both its image embedding and its enriched-text embedding, taking the max.

## Pipeline

`ShelfProcessor` (a `@ModelActor` with its own SwiftData context) drains a serial queue — one item in flight, because concurrent Core ML + LLM calls on a phone cause memory spikes and thermal throttling, not speedups. Capture inserts the item as `.queued` and returns immediately; the UI never blocks on inference. Progress persists after every step, so a mid-item kill loses at most one step. On launch, reconciliation re-queues anything stranded in `.processing`/`.queued` and re-embeds items with stale model versions. Hard failures (undecodable image) set `.failed` with a message and a **Try again** button in the detail view; partial results always win over discarding. The Live Activity is driven by real pipeline state via value snapshots — SwiftData model objects never cross actor boundaries.

## Verification

- **Tests** (`coveTests`, 18 passing): tokenizer parity against Python fixtures, embedding normalization/determinism/dimension invariants on the real Core ML models, hybrid-search ranking on fixed fixtures (keyword hit outranks, semantic floor drops orthogonal items, stale-dimension vectors skipped), extraction JSON round-trips, and pipeline state transitions including the failure and reconciliation paths.
- **Offline claim**: the app links no networking API — audited: no `URLSession`/`CFNetwork`/`Network` usage anywhere; locally supplied models, Foundation Models, and Vision run on-device by design; the Live Activity uses `pushType: nil`. Saved link URLs are stored, never fetched. Confirm end-to-end on hardware by enabling airplane mode and running capture → search.
- **Measured latency** (Apple-silicon Mac via Core ML, batch 1, after warm-up — device numbers must be collected on hardware via the AI Diagnostics screen): image encoder 1.2 ms (`.all`) / 9.1 ms (CPU-only); text encoder ~5–7 ms. Simulator end-to-end (screenshot capture → OCR → both embeddings → ready, language model unavailable there): ~2 s including first model load.

> **Note**: an iOS 26 device is required for on-device Foundation Models and for real latency/thermal numbers. The attached test iPhone on iOS 18 cannot run this build.

## Build

Open `cove.xcodeproj`, choose the `cove` scheme, select an iPhone 16 Pro simulator running iOS 26, and Run.

Command-line build:

```sh
xcodebuild \
  -project cove.xcodeproj \
  -scheme cove \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  build
```

Live Activities must be enabled for the app in the simulator. The Dynamic Island is a status surface only; it is not a capture target.

## Set up the Action Button

The installed iOS 26 SDK exposes foreground App Intents through `supportedModes`; Cove’s **Quick Capture** shortcut uses `.foreground(.immediate)`. The Action Button launches the real app capture sheet, while the Dynamic Island opens a **Ready to capture** Live Activity. After submission, the same activity changes to the processing title/count and ends when processing reaches zero. Apple does not permit arbitrary app UI inside the Dynamic Island.

1. Launch Cove once so iOS indexes its App Shortcut.
2. Open **Settings → Action Button** and select **Shortcut**.
3. Choose **Quick Capture** under Cove.
4. On a device, press the Action Button. In Simulator, use **Device → Action Button**.
5. If iOS asks to allow Live Activities for Cove the first time, choose **Allow**.
6. Cove opens directly to **Add to Cove**, and the Dynamic Island shows Cove’s capture status.

On iPhones without an Action Button, the same App Shortcut can be launched with Siri or Spotlight. For a hardware gesture, create a one-action shortcut using Cove's **Quick Capture** action, then assign it under **Settings → Accessibility → Touch → Back Tap**. It can also live in a Shortcuts Home Screen widget or Control Center. Phones without Dynamic Island hardware still receive the Live Activity on the Lock Screen.

## Record the Phase 1 demo

1. Delete Cove from the simulator first if you want a clean empty store, then launch once and configure the Action Button as above.
2. Launch Cove on an iPhone 16 Pro simulator with Reduce Motion off.
3. Hold for a moment on the empty shelf so the animated Metal caustic is visible behind the empty state.
4. Use **Device → Action Button**. Show Cove opening to **Add to Cove** and the **Ready to capture** Dynamic Island status.
5. Choose **Note**, enter title `Kyoto coffee list`, and enter `Try Weekenders Coffee near Kawaramachi and save the pour-over menu.`
6. Tap **Add**. Show the processing spinner on the glass card and the Cove count in the Dynamic Island.
7. Wait for the card to become ready, then open it. Show the mock summary, tags, and locally stored note.
8. Tap **Chat about this**, send the prefilled question, and show the clearly labeled mock response.
9. Close chat and tap **Add to Calendar** or **Add Reminder** to show the Phase 1 no-write disclosure.
10. Return to the shelf, open **Search your shelf**, and search for `coffee` or `Kawaramachi`.
11. Open the returned card to finish on the useful result.

For the image path, repeat with **Add → Photo**, choose a screenshot, and show the fake OCR receipt text after processing. To demonstrate accessibility behavior, enable **Settings → Accessibility → Motion → Reduce Motion** and relaunch; the Metal backdrop remains static.
