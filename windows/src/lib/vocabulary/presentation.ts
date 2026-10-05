import type { LearningStatusPresentation } from "../types/vocabulary";
const labels: Record<LearningStatusPresentation, string> = { unlearned: "未学习", reviewing: "复习中", mastered: "已熟练" };
export const learningStatusLabel = (status: LearningStatusPresentation): string => labels[status];
