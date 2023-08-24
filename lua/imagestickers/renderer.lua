local ImageStickers = ImageStickers

local render_DrawQuad = render.DrawQuad
local render_DrawBox = render.DrawBox
local render_SetMaterial = render.SetMaterial
local surface_DrawRect = surface.DrawRect
local surface_SetDrawColor = surface.SetDrawColor
local surface_SetFont = surface.SetFont
local surface_GetTextSize= surface.GetTextSize
local draw_SimpleText = draw.SimpleText
local surface_DrawOutlinedRect = surface.DrawOutlinedRect
local Vector = Vector
local render_DrawLine = render.DrawLine
local Angle = Angle

local renderDebuggingInformation = false
local renderIndex = 0

local hoveredEnt

local badParents = {
    ["ContextMenu"] = true,
    ["GModBase"] = true,
}

hook.Add("RenderScene", "march.imagestickers.reset_render_order", function()
    renderIndex = 0

    local p = vgui.GetHoveredPanel()
    if IsValid(p) then
        for i = 1, 3000 do
            local tp = p:GetParent()
            if not IsValid(tp) or badParents[tp:GetName()] == true then break end
            p = tp
        end
        --determine hovered entity
        if p.IsImageStickerDialog == true then
            hoveredEnt = p.Properties.m_Entity
        else
            hoveredEnt = nil
        end
    else
        hoveredEnt = nil
    end
end)

local curtime = CurTime
function ImageStickers.UpdateAnimatedBorder(self, on)
    if self.animateOn == false and on then
        self.animateCurtimeStart = curtime()
    end
    self.animateOn = on
end

function ImageStickers.RenderAnimatedBorder(self, w, h)
    if not self.animateOn then return end

    local now = curtime()
    local animationTime = now - self.animateCurtimeStart

    local offset = animationTime % 1
    local offsetV = math.ease.OutElastic(offset) * 32
    local alphaA = math.ease.OutQuad(offset) * 255
    surface.SetDrawColor(Color(200, 235, 255, 255 - alphaA))
    
    surface.DrawLine(-w - offsetV, -h - offsetV, w + offsetV, -h - offsetV) --top line
    surface.DrawLine(-w - offsetV, h + offsetV, w + offsetV, h + offsetV) --bottom line

    surface.DrawLine(-w - offsetV, h + offsetV, -w - offsetV, -h - offsetV) --left line
    surface.DrawLine(w + offsetV, h + offsetV, w + offsetV, -h - offsetV) --right line
end

function ImageStickers.GetFlags(self)
    local additive = self:GetAdditive() == true and 128 or 0
    local enableAlphaTest = self:GetShouldImageTestAlpha() == true and 256 or 0
    local translucent = self:GetTranslucency() == true and 2097152 or 0
    local nocull = self:GetNocull() == true and 8192 or 0

    return additive + enableAlphaTest + translucent + nocull
end

local math_Clamp = math.Clamp
local render_SuppressEngineLighting = render.SuppressEngineLighting
local Matrix = Matrix

function ImageStickers.GetBorderRect3D(self)
    local image = self.image

    local w, h = 0, 0

    if image ~= nil and image.errored == false and image.material ~= nil then
        local imageScale = self:GetImageScale()
        local imageScaleX, imageScaleY = math_Clamp(imageScale * self:GetImageScaleX(), 0, 32), math_Clamp(imageScale * self:GetImageScaleY(), 0, 32)
        
        local tw, th = image.width / 3, image.height / 3
        tw = tw * 0.08
        th = th * 0.08

        h = math_Clamp(tw * imageScaleX, 0.1, 9000000) 
        w = math_Clamp(th * imageScaleY, 0.1, 90000000) 
    else
        w = 146 * 0.08
        h = 146 * 0.08
    end

    return {
        TL = self:LocalToWorld(Vector(-w*1,-h*1,1.6)),
		TR = self:LocalToWorld(Vector(-w*1,h*1,1.6)),
		BL = self:LocalToWorld(Vector(w*1,-h*1,1.6)),
		BR = self:LocalToWorld(Vector(w*1,h*1,1.6))
    }
end

function ImageStickers.RenderImageOntoSticker(self)
    --local stopwatchStart = SysTime()
    ImageStickers.UpdateAnimatedBorder(self, hoveredEnt == self)

    local lv, la = self:LocalToWorld(Vector(0, 0,0.5)), self:LocalToWorldAngles(Angle(0,90,00))
    local TextResult = ""
    local image = self.image
    local imageScale = self:GetImageScale()
    local image_errored, image_error, image_loading, image_material

    if image ~= nil then
        image_errored = image.errored
        image_error = image.error
        image_loading = image.loading
        image_material = image.material
    end
    
    local shouldDraw2D = true
    local w, h = 0, 0
    local isRenderingImage = false

    if image == nil then
        TextResult = ImageStickers.Language.GetPhrase("imagesticker.nourl", "No URL")
    else
        if image_errored ~= true and image_loading ~= true then
            shouldDraw2D = false
            TextResult = nil

            w, h = image.width / 3, image.height / 3

            local imageScaleX, imageScaleY = math_Clamp(imageScale * self:GetImageScaleX(), 0, 32), math_Clamp(imageScale * self:GetImageScaleY(), 0, 32)

            w = math_Clamp(w * imageScaleX, 0.1, 9000000) 
            h = math_Clamp(h * imageScaleY, 0.1, 90000000) 
            
            self:SetRenderBounds(Vector(-w, -h, -1), Vector(w, h, 1))

            if self:GetShouldImageGlow() then render_SuppressEngineLighting(true) end

            render_SetMaterial(image_material)

            local m = Matrix()
                m:Translate(self:GetPos())
                m:Rotate(self:GetAngles())
                m:Scale(Vector(1, 1, 1))

            local c = self:GetColor()
            image.material:SetVector("$color", Vector(c.r / 255, c.g / 255, c.b / 255))
            image.material:SetFloat("$alpha", c.a / 255)
            image.material:SetInt("$flags", ImageStickers.GetFlags(self))
            
            isRenderingImage = true
            cam.PushModelMatrix(m)
                render.DrawQuadEasy(Vector(0, 0, -1.45), Vector(0,0,1), w/6.252, h/6.252, color_white, 180 - self:GetImageAngle())
            cam.PopModelMatrix()

            render.SuppressEngineLighting(false) 
        end
    end

    local drawRenderAnimatedBorder = hoveredEnt == self
    
    if drawRenderAnimatedBorder or shouldDraw2D or renderDebuggingInformation then
        cam.Start3D2D(lv, la, 0.08)
            if image == nil then
                TextResult = ImageStickers.Language.GetPhrase("imagesticker.nourl", "No URL")
            else
                if image_errored ~= true and image_loading ~= true then
                    TextResult = nil
                    
                    if renderDebuggingInformation then
                        render_DrawLine(Vector(w, -h, -2), Vector(w, h, -2))
                        render_DrawLine(Vector(-w, -h, -2), Vector(w, -h, -2))
                        render_DrawLine(Vector(-w, -h, -2), Vector(-w, h, -2))
                        render_DrawLine(Vector(-w, h, -2), Vector(w, h, -2))

                        draw_SimpleText("Image angle: " .. self:GetImageAngle(), "DermaDefault", -image.width/2,image.height/2)
                        draw_SimpleText("Image scale X: " .. self:GetImageScaleX(), "DermaDefault", -image.width/2,(image.height/2) + (16 * 1) )
                        draw_SimpleText("Image scale Y: " .. self:GetImageScaleY(), "DermaDefault", -image.width/2,(image.height/2) + (16 * 2) )
                        draw_SimpleText("Image scale: " .. self:GetImageScale(), "DermaDefault", -image.width/2,(image.height/2) + (16 * 3) )
                        draw_SimpleText("Rendering Order: " ..renderIndex, "DermaLarge", -image.width/2,(image.height/2) + (16 * 4) )
                    end
                end

                if image_loading then
                    TextResult = ImageStickers.Language.GetPhrase("imagesticker.loading", "Loading...")
                end
                if image_errored then
                    TextResult = ImageStickers.Language.GetPhrase("imagesticker.errored", "Errored:") .. " " .. image_error
                end
            end
            
            if drawRenderAnimatedBorder then
                if not isRenderingImage then
                    w = 146 * 1
                    h = 146 * 1
                end
                ImageStickers.RenderAnimatedBorder(self, w, h)
            end

            local boxSize = 146
            if TextResult ~= nil or image_errored then
                surface_SetFont("DermaDefault")
                local X, Y = surface_GetTextSize(TextResult)
                local padding = 12
                X = X + padding
                Y = Y + padding
                
                surface_SetDrawColor(0, 0, 0, 125)
                surface_DrawOutlinedRect(-boxSize, -boxSize, boxSize*2, boxSize*2, 8)
                surface_DrawRect(-X / 2, -Y / 2, X, Y)
                draw_SimpleText(TextResult or image_error, "DermaDefault", 0, 0, c ,TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    --print("took " .. ((SysTime() - stopwatchStart) * 1000) .. " ms")
    renderIndex = renderIndex + 1
end