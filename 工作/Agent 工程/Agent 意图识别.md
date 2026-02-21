1. 咨询与业务执行职责分离
2. 轻量级 LLM 意图路由
3. 固定需要进行数据检测的进行硬编码处理。
	1. 怎么解决 prompt 权重应该大于 选中资产？比如 selectedAssets 列表中包含了[COMP-1,COMP-2]，但 user prompt 为 "仅识别 COMP-2"。那么就应该只处理 COMP-2
		