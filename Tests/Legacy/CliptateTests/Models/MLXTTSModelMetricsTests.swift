import Testing
@testable import Cliptate

@Suite("MLXTTSModelDefinition Metrics Tests")
struct MLXTTSModelMetricsTests {
    
    @Test("Model has metric chips data")
    func testMetricChipsData() {
        let model = MLXTTSModelDefinition.availableModels[0]
        let chips = model.metricChips
        
        #expect(chips.count == 4)
        #expect(chips[0].title == "SIZE")
        #expect(chips[1].title == "DOWNLOAD")
        #expect(chips[2].title == "QUANTIZATION")
        #expect(chips[3].title == "FAMILY")
    }
    
    @Test("0.6B model shows correct size")
    func testModelSize06B() {
        let model = MLXTTSModelDefinition.availableModels.first { $0.parameterSize == "0.6B" }!
        let sizeChip = model.metricChips[0]
        #expect(sizeChip.value == "0.6B")
        #expect(sizeChip.icon == "cube.fill")
    }
    
    @Test("1.7B model shows correct size")
    func testModelSize17B() {
        let model = MLXTTSModelDefinition.availableModels.first { $0.parameterSize == "1.7B" }!
        let sizeChip = model.metricChips[0]
        #expect(sizeChip.value == "1.7B")
    }
    
    @Test("Download size chip shows MB")
    func testDownloadSize() {
        let model = MLXTTSModelDefinition.availableModels[0]
        let downloadChip = model.metricChips[1]
        #expect(downloadChip.value.contains("MB"))
        #expect(downloadChip.icon == "arrow.down.circle.fill")
    }
    
    @Test("Quantization chip shows quantization level")
    func testQuantization() {
        let model4bit = MLXTTSModelDefinition.availableModels.first { $0.quantization == "4-bit" }!
        let quantChip = model4bit.metricChips[2]
        #expect(quantChip.value == "4-bit")
        #expect(quantChip.icon == "speedometer")
    }
    
    @Test("Family chip shows family name")
    func testFamilyChip() {
        let baseModel = MLXTTSModelDefinition.availableModels.first { $0.family == .base }!
        let familyChip = baseModel.metricChips[3]
        #expect(familyChip.value == "Base")
        #expect(familyChip.icon == "waveform.badge.mic")
    }
    
    @Test("Base family has correct icon and color")
    func testBaseFamilyVisual() {
        let model = MLXTTSModelDefinition.availableModels.first { $0.family == .base }!
        let visual = model.familyVisual
        #expect(visual.icon == "person.wave.2.fill")
        #expect(visual.colorName == "orange")
    }
    
    @Test("Curated catalog keeps only Base family")
    func testCatalogIsBaseOnly() {
        #expect(MLXTTSModelDefinition.availableModels.allSatisfy { $0.family == .base })
    }
}
