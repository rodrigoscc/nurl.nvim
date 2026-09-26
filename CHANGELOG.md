# Changelog

## [1.0.0](https://github.com/rodrigoscc/nurl.nvim/compare/v0.10.0...v1.0.0) (2026-09-26)


### ⚠ BREAKING CHANGES

* NurlWinbarSuccessStatusCode, NurlWinbarErrorStatusCode, NurlInfoStatus* and NurlHistoryStatus* are replaced by NurlStatus, NurlStatusSuccess, NurlStatusRedirect, NurlStatusClientError and NurlStatusServerError, with matching highlight.groups keys. The Test tab uses NurlTestFail when tests fail.
* replace history picker with history explorer

### Features

* convert between JSON and Lua tables ([587c05e](https://github.com/rodrigoscc/nurl.nvim/commit/587c05eca4789196fe1d40d3c8a95040585cf260))
* delete history entries from the explorer ([927edb2](https://github.com/rodrigoscc/nurl.nvim/commit/927edb273fb95b6e87eaad15985200886235819a))
* filter history by responses saved to a file ([e11faaa](https://github.com/rodrigoscc/nurl.nvim/commit/e11faaaea9a05ef5d9e0a69f660fc2e3de50d241))
* limit history by item count instead of disk size ([847f0d2](https://github.com/rodrigoscc/nurl.nvim/commit/847f0d24e4bf68861cccea74c3ec3d899866568d))
* preview requests and fill visible history pages ([2f47e7d](https://github.com/rodrigoscc/nurl.nvim/commit/2f47e7dda399fa9bc10451fde6c44283106f13d6))
* replace history picker with history explorer ([4573469](https://github.com/rodrigoscc/nurl.nvim/commit/45734693ed9615b0e66ccb5e277c8c74a7585e34))
* retain request history by disk size ([137dd91](https://github.com/rodrigoscc/nurl.nvim/commit/137dd9117e1b8de52a93fa57e2dd55f551e67ccc))
* show relative dates in the history explorer ([e42a016](https://github.com/rodrigoscc/nurl.nvim/commit/e42a0165f63178a54eede9c9b76a19248d4f7e1e))
* use the same status code colors in every view ([e1d02c1](https://github.com/rodrigoscc/nurl.nvim/commit/e1d02c1a51295f1aaff4fa3143afa3f5f54e5b5f))


### Bug Fixes

* bind every statement parameter after a nil value ([df65365](https://github.com/rodrigoscc/nurl.nvim/commit/df6536536af3313423a7999106ce6fcdda655d6e))
* close the history database when opening it fails ([60f15ca](https://github.com/rodrigoscc/nurl.nvim/commit/60f15cac8ebcfc8b3c438c4cc50ed4e5def22dfb))
* do not leave an empty buffer when opening the history explorer ([bba7a44](https://github.com/rodrigoscc/nurl.nvim/commit/bba7a44112cf2bbc3c9750a9bf19f3d4b7fa79a0))
* keep the history explorer usable when it is the last tab page ([a8c9adc](https://github.com/rodrigoscc/nurl.nvim/commit/a8c9adca2644338cb107d795667dabe049e4d802))
* locate history worker modules outside runtimepath ([54fe755](https://github.com/rodrigoscc/nurl.nvim/commit/54fe7553229da3bba0e74af4ea65f1caffc672a9))
* remove saved response files safely in history worker ([d4749e5](https://github.com/rodrigoscc/nurl.nvim/commit/d4749e53da7edd2173d6e5026779947254ccc015))
* show response headers in the order the server sent them ([c2bc311](https://github.com/rodrigoscc/nurl.nvim/commit/c2bc311deddda4b4534d236b6ed0040769d3d376))
* show responses without timing or size values ([f085e33](https://github.com/rodrigoscc/nurl.nvim/commit/f085e33ca01774f0f9fe8e07b3213e766139d401))
* toggle the info split with gi instead of Enter ([6ec011a](https://github.com/rodrigoscc/nurl.nvim/commit/6ec011a01887ed2f827c5e492ce89c54458eba13))


### Performance Improvements

* delete old history entries in batches ([184d373](https://github.com/rodrigoscc/nurl.nvim/commit/184d3731410ad4c2387b360d5edaf1f61eb02ef0))
* do not sync history to disk on every saved request ([8b8ede3](https://github.com/rodrigoscc/nurl.nvim/commit/8b8ede3b710c00df6dbe54c59603ca10add22926))
* run history filters that scan every entry in a background worker ([74811de](https://github.com/rodrigoscc/nurl.nvim/commit/74811de3b9e72b1b324589bdbe56b654c7a58b0d))
* skip counting history while it is under the item limit ([f250b22](https://github.com/rodrigoscc/nurl.nvim/commit/f250b220c9ae62810428501073a6d6a06ca8bbc1))

## [0.10.0](https://github.com/rodrigoscc/nurl.nvim/compare/v0.9.0...v0.10.0) (2026-05-12)


### Features

* add save_history request field to disable history per request ([a663158](https://github.com/rodrigoscc/nurl.nvim/commit/a6631581edd29938c861baf6c85244f5b0571212))
* request tab shows fully expanded request ([a307ca6](https://github.com/rodrigoscc/nurl.nvim/commit/a307ca6e872c13709225da42c7a377a5730fbb7d))

## [0.9.0](https://github.com/rodrigoscc/nurl.nvim/compare/v0.8.0...v0.9.0) (2026-05-12)


### Features

* add method to winbar, remove proto and compact time ([d442425](https://github.com/rodrigoscc/nurl.nvim/commit/d4424252920c352cd7c953aa2472327e595d5b9d))
* improve info buffer layout and add timing bars ([6bb0906](https://github.com/rodrigoscc/nurl.nvim/commit/6bb09068aaa370a1b2ce492fb6d0934996fc694e))


### Bug Fixes

* empty responses should be considered displayable ([7592557](https://github.com/rodrigoscc/nurl.nvim/commit/7592557df5e4a4a83cd4905548ee87aa10c51f70))
* keep the tip item updated ([6da7077](https://github.com/rodrigoscc/nurl.nvim/commit/6da707768dda70c9c9e5c7cbc7abcf110c987dab))
* stack should skip pushing same item as the last one ([dadea09](https://github.com/rodrigoscc/nurl.nvim/commit/dadea093d0fb45cbf623d0adcb4993f71b0070db))
