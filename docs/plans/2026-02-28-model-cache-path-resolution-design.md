# Model Cache Path Resolution Design

## Problem

在 `.worktree` 中运行 app 时，已下载模型会被误判为不存在并触发 HuggingFace 重新下载；主目录运行通常正常。  
根因是**模型缓存路径解析与探测过于单一路径**，而实际机器上同时存在多种历史/上下文路径（如容器路径、用户文档路径、`huggingface/hub` 结构路径）。

## Evidence

本机已存在以下并行缓存布局：

- Whisper:
  - `~/Library/Containers/com.voicepink.voicepinkpro/Data/Documents/huggingface/models/argmaxinc/whisperkit-coreml/...`
  - `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/...`
- MLXAudio (Qwen3/TTS):
  - `~/Library/Containers/com.voicepink.voicepinkpro/Data/Library/Caches/mlx-audio/...`
  - `~/Library/Containers/com.voicepink.voicepinkpro/Data/Library/Caches/huggingface/hub/mlx-audio/...`

当前实现对不同模型族使用的探测根路径不一致，导致“模型已存在但未命中”。

## Goal

统一并增强模型缓存探测：**优先复用已存在模型，只有全部候选路径都不存在时才下载**，消除 worktree/main 运行差异导致的重复下载。

## Approach (Approved)

选择方案 A：多路径探测并复用已有模型（最小行为变更、风险最低）。

## Architecture

1. 在 `ModelCacheDirectory` 增加候选根路径解析能力（含当前路径 + 历史兼容路径）。
2. Whisper/Qwen3/TTS 下载管理器统一调用该解析层进行本地命中判断。
3. 下载流程保持不变，仅替换“是否已下载”的判定逻辑和目录返回逻辑。

## Data Flow

1. `isModelDownloaded/getModelDirectory` 调用统一“候选路径列表”。
2. 依序探测每个候选路径是否存在完整模型文件。
3. 命中即返回；若多个命中，优先当前默认路径。
4. 全部未命中时再触发下载。

## Error Handling

- 不做静默兜底成功：路径存在但文件不完整时记录明确日志，并继续探测下一个候选。
- 全部候选都不完整才进入下载。
- 保持原有下载异常抛出语义。

## Testing

补充/更新测试覆盖：

1. 多路径命中优先级正确。
2. 历史路径可复用，不触发重复下载。
3. 路径不完整时继续探测后续候选。
4. 相对环境变量路径归一化后稳定（避免 worktree cwd 差异影响）。

## Non-Goals

- 不改 UI 行为。
- 不引入新的下载源或并发下载策略。
