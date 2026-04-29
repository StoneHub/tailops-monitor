export function getScreenMode({ width, height }) {
  if (width < 700 || height < 540) return "tiny";
  if (width < 1200 || height < 720) return "compact";
  return "wide";
}

export function getNodeLabelPolicy(mode) {
  if (mode === "tiny") return { showSecondary: false, maxLength: 10, fontScale: 0.82 };
  if (mode === "compact") return { showSecondary: false, maxLength: 16, fontScale: 0.92 };
  return { showSecondary: true, maxLength: 22, fontScale: 1 };
}
