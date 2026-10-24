import { describe, expect, it } from "vitest"
import { overlayRenderLimits } from "showrunner-overlay-core"
import { readShaderFrameInputs, shaderSurfaceSize, ShaderFrameInputSource } from "./shader-render-input"

const source = (): ShaderFrameInputSource => ({getAccentColor:()=>[1,0,0],getSecondaryColor:()=>[0,1,0],getIntensity:()=>1,getSpeed:()=>1})
describe("typed shader render inputs",()=>{
  it.each([NaN,Infinity,1e100])("rejects a non-finite GPU scalar %s before upload", value=>{
    expect(()=>readShaderFrameInputs({...source(),getIntensity:()=>value})).toThrow("finite")
  })
  it("bounds uniform counts, names and vector components",()=>{
    const custom=Object.fromEntries(Array.from({length:overlayRenderLimits.maxShaderUniforms+1},(_,index)=>[`u_${index}`,1]))
    expect(()=>readShaderFrameInputs({...source(),getCustomUniforms:()=>custom})).toThrow("limit")
    expect(()=>readShaderFrameInputs({...source(),getCustomUniforms:()=>({"bad name":1})})).toThrow("name")
    expect(()=>readShaderFrameInputs({...source(),getCustomUniforms:()=>({u_vec:[1,2,3,4,5]})})).toThrow("components")
  })
  it("copies vector inputs and bounds the surface while preserving aspect ratio",()=>{
    const vector=[1,2,3]
    const inputs=readShaderFrameInputs({...source(),getCustomUniforms:()=>({u_vec:vector})})
    vector[0]=99
    expect(inputs.uniforms.u_vec).toEqual([1,2,3])
    expect(shaderSurfaceSize(320,180,2,4096)).toEqual({width:640,height:360})
    expect(shaderSurfaceSize(8192,4096,2,2048)).toEqual({width:2048,height:1024})
    expect(shaderSurfaceSize(Infinity,NaN,Infinity,4096)).toEqual({width:1,height:1})
  })
})
