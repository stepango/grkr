export function parse_int(str) {
  const num = parseInt(str, 10);
  if (isNaN(num)) {
    return ["Error", undefined];
  }
  return ["Ok", num];
}
