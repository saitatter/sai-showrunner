import { overlayRenderLimits } from "showrunner-overlay-core"

export interface ShaderFrameInputSource {
  getAccentColor: () => [number, number, number]
  getSecondaryColor: () => [number, number, number]
  getIntensity: () => number
  getSpeed: () => number
  getCustomUniforms?: () => Record<string, number | number[]>
}

const finite = (value: number) => Number.isFinite(value) && Number.isFinite(Math.fround(value))
function scalar(value: number): number {
  if (!finite(value)) throw new Error("Shader inputs require finite scalar/vector values.")
  return value
}

/** Snapshot typed renderer inputs before issuing any WebGL uniform writes. */
export function readShaderFrameInputs(source: ShaderFrameInputSource) {
  const accent = source.getAccentColor().map(scalar) as [number,number,number]
  const secondary = source.getSecondaryColor().map(scalar) as [number,number,number]
  if (accent.length !== 3 || secondary.length !== 3) throw new Error("Shader colors require three components.")
  const custom = source.getCustomUniforms?.() ?? {}
  const uniforms: Record<string, number | number[]> = {}
  if (Object.keys(custom).length > overlayRenderLimits.maxShaderUniforms) throw new Error("Shader uniform limit exceeded.")
  for (const [name,value] of Object.entries(custom)) {
    if (name.length > 128 || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error("Invalid shader uniform name.")
    if (Array.isArray(value)) {
      if (value.length < 2 || value.length > 4) throw new Error("Shader vectors require two to four components.")
      uniforms[name] = value.map(scalar)
    } else uniforms[name] = scalar(value)
  }
  return {accent,secondary,intensity:scalar(source.getIntensity()),speed:scalar(source.getSpeed()),uniforms}
}

export function shaderSurfaceSize(width: number, height: number, ratio: number, hardwareLimit: number) {
  const w = Number.isFinite(width) ? Math.max(1,width) : 1
  const h = Number.isFinite(height) ? Math.max(1,height) : 1
  const pixelRatio = Number.isFinite(ratio) ? Math.max(1,Math.min(ratio,2)) : 1
  const limit = Math.min(overlayRenderLimits.maxShaderSurfaceDimension, Number.isFinite(hardwareLimit) && hardwareLimit >= 1 ? hardwareLimit : overlayRenderLimits.maxShaderSurfaceDimension)
  const scale = Math.min(pixelRatio,limit/w,limit/h)
  return {width:Math.max(1,Math.floor(w*scale)),height:Math.max(1,Math.floor(h*scale))}
}
