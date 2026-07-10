import { cwd } from "process";

export function getcwd() {
  return { 0: cwd(), 1: undefined };
}