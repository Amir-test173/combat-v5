export const PACE_SECONDS={rapid:300,campaign:3600,grand:43200};
export function safePace(value){return Object.hasOwn(PACE_SECONDS,String(value||''))?String(value):'campaign'}
export function turnSecondsForPace(value,override=null){const n=Number(override);return Number.isFinite(n)&&n>0?Math.round(n):PACE_SECONDS[safePace(value)]}
export function hegemonyStartTurn(value){return safePace(value)==='rapid'?15:(safePace(value)==='grand'?40:25)}
export function commandBaseForPace(value){return safePace(value)==='rapid'?8:(safePace(value)==='grand'?5:6)}
export function provinceReadiness(province={}){const infra=Math.max(0,Math.min(100,Number(province.infrastructure??60))),supply=Math.max(0,Math.min(100,Number(province.supply??70)));return (.72+infra/180)*(.70+supply/230)}
