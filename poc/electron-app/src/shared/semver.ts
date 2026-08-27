import { compare as semverCompare, valid } from 'semver';

export function compareSemver(a: string, b: string): -1 | 0 | 1 {
  if (!valid(a)) throw new Error(`invalid semver: ${a}`);
  if (!valid(b)) throw new Error(`invalid semver: ${b}`);
  return semverCompare(a, b) as -1 | 0 | 1;
}
export const gt = (a: string, b: string) => compareSemver(a, b) > 0;
export const lte = (a: string, b: string) => compareSemver(a, b) <= 0;
export const gte = (a: string, b: string) => compareSemver(a, b) >= 0;
export const isValid = (v: string): boolean => valid(v) !== null;
