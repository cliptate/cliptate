# Third-party notices

The repository's MIT license covers Cliptate's own code. Dependencies, bundled
third-party components, and downloaded model weights retain their upstream licenses.
Dependency copyright notices are preserved in [docs/legal/dependencies](docs/legal/dependencies).
The license overview is based on upstream license texts, with the versions selected
by the committed dependency locks.

## Direct dependencies

| Dependency | License | Upstream |
| --- | --- | --- |
| KeyboardShortcuts | MIT | https://github.com/sindresorhus/KeyboardShortcuts |
| LaunchAtLogin Modern | MIT | https://github.com/sindresorhus/LaunchAtLogin-Modern |
| SwiftAssRenderer | MIT | https://github.com/mihai8804858/swift-ass-renderer |
| Combine Schedulers | MIT | https://github.com/pointfreeco/combine-schedulers |
| XCTest Dynamic Overlay | MIT | https://github.com/pointfreeco/xctest-dynamic-overlay |
| AudioKit | MIT | https://github.com/AudioKit/AudioKit |
| RevenueCat | MIT | https://github.com/RevenueCat/purchases-ios-spm |
| MLX Audio Swift | MIT | https://github.com/Blaizzy/mlx-audio-swift |
| MLX Swift | MIT | https://github.com/ml-explore/mlx-swift |
| MLX Swift LM | MIT | https://github.com/ml-explore/mlx-swift-lm |
| Hugging Face Swift | Apache-2.0 | https://github.com/huggingface/swift-huggingface |

The exact dependency graph and revisions are recorded in `Package.resolved` and
the Xcode project's resolved file. License copies include the resolved transitive
Swift packages. Updates must preserve the upstream notices for the selected revisions.

SwiftAssRenderer additionally depends on SwiftLibass and its binary components;
those components' notices and licenses must accompany redistributed binaries.
Cliptate does not relicense those binaries under MIT. SwiftLibass's prebuilt
components have the following upstream notices, preserved in
[docs/legal/binary-dependencies](docs/legal/binary-dependencies):

| Component | Prebuilt version | License |
| --- | --- | --- |
| Fontconfig | 2.15.0 | Fontconfig permissive license |
| FreeType | 2.13.2 | FreeType License (FTL) or GPL-2.0; FTL text included |
| FriBidi | 1.0.14 | LGPL-2.1-or-later |
| HarfBuzz | 8.5.0 | MIT-style permissive license |
| libpng | 1.6.43 | PNG Reference Library License |
| libass | 0.17.3 | ISC |

These versions are reported by SwiftLibass's upstream README. In particular,
FriBidi's LGPL terms apply independently to binary distribution; include its license
and follow the source/relinking provisions of the selected upstream license when
shipping an application linked to it. The MIT license of the Swift wrapper does not
replace those terms.

## Models

Model weights are downloaded at runtime and are not included in this repository.
Check each selected model's Hugging Face model card and license before redistributing
weights or deploying a derived application. ASR, VAD, diarization, forced alignment,
and TTS models can have different terms; the inference library's license does not
replace a model's license. Model identifiers are defined in the app's model catalog.

## Attribution and distribution

Original author headers from WhisperCutPro are retained. Cliptate application assets
and tracked development fixtures are migrated with the project; future contributors
must supply provenance and permission for additional media. The Cliptate name and
App Store listing identify the upstream application and do not transfer ownership
of the upstream store account or subscription products.

When distributing a compiled app, include dependency license and notice texts alongside
the app or in an accessible acknowledgments section, including notices shipped with
binary frameworks. This source repository includes its dependency notice copies to
support that process.
