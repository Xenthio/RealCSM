local function CheckLightmapAlpha()
    local tex = render.GetLightmapTexture()
    if not tex then print("No lightmap texture found!") return end

    -- Render lightmap to a small RT so we can read pixels
    local rt = GetRenderTarget("CheckAlphaRT", 16, 16)
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 255)
    
    -- Draw lightmap to RT
    render.SetMaterial(CreateMaterial("CheckAlphaMat", "UnlitGeneric", { ["$basetexture"] = tex:GetName() }))
    render.DrawScreenQuad()
    
    -- Capture and check pixels
    local data = render.CapturePixels()
    render.PopRenderTarget()

    local hasAlpha = false
    local sampleSize = 10
    for y = 1, sampleSize do
        for x = 1, sampleSize do
            local _, _, _, a = render.ReadPixel(x, y)
            if a < 250 then -- If it's not basically 255, we found data
                hasAlpha = true
                print(string.format("Found Mask! Pixel (%d,%d) Alpha: %d", x, y, a))
                break
            end
        end
        if hasAlpha then break end
    end

    if not hasAlpha then
        print("Result: All pixels are Opaque (Alpha 255). No mask data found.")
    else
        print("Result: Success! Variation detected in Alpha channel.")
    end
end
CheckLightmapAlpha()
