// 与 Rust 校验保持一致；永久表示保持至用户关闭或退出应用。
export const DURATIONS = [
  { label: '永久', seconds: null },
  { label: '5 分钟', seconds: 300 },
  { label: '30 分钟', seconds: 1800 },
  { label: '1 小时', seconds: 3600 },
  { label: '2 小时', seconds: 7200 },
  { label: '5 小时', seconds: 18000 },
  { label: '8 小时', seconds: 28800 },
] as const;
