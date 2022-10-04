function ImGui_ImplOpenGL2_SetupRenderState(ctx::Context, draw_data, fb_width::Cint, fb_height::Cint)
    # Setup render state:
    # - alpha-blending enabled
    # - no face culling
    # - no depth testing
    # - scissor enabled
    # - vertex/texcoord/color pointers
    # - polygon fill
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    #glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA); # In order to composite our output buffer we need to preserve alpha
    glDisable(GL_CULL_FACE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_STENCIL_TEST)
    glDisable(GL_LIGHTING)
    glDisable(GL_COLOR_MATERIAL)
    glEnable(GL_SCISSOR_TEST)
    glEnableClientState(GL_VERTEX_ARRAY)
    glEnableClientState(GL_TEXTURE_COORD_ARRAY)
    glEnableClientState(GL_COLOR_ARRAY)
    glDisableClientState(GL_NORMAL_ARRAY)
    glEnable(GL_TEXTURE_2D)
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
    glShadeModel(GL_SMOOTH)
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE)

    # If you are using this code with non-legacy OpenGL header/contexts (which you should not, prefer using imgui_impl_opengl3.cpp!!),
    # you may need to backup/reset/restore other state, e.g. for current shader using the commented lines below.
    # (DO NOT MODIFY THIS FILE! Add the code in your calling function)
    #   GLint last_program;
    #   glGetIntegerv(GL_CURRENT_PROGRAM, &last_program);
    #   glUseProgram(0);
    #   ImGui_ImplOpenGL2_RenderDrawData(...);
    #   glUseProgram(last_program)
    # There are potentially many more states you could need to clear/setup that we can't access from default headers.
    # e.g. glBindBuffer(GL_ARRAY_BUFFER, 0), glDisable(GL_TEXTURE_CUBE_MAP).

    # Setup viewport, orthographic projection matrix
    # Our visible imgui space lies from draw_data->DisplayPos (top left) to draw_data->DisplayPos+data_data->DisplaySize (bottom right). DisplayPos is (0,0) for single viewport apps.
    glViewport(0, 0, GLsizei(fb_width), GLsizei(fb_height))
    glMatrixMode(GL_PROJECTION)
    glPushMatrix()
    glLoadIdentity()
    disp_pos = unsafe_load(draw_data.DisplayPos)
    disp_size = unsafe_load(draw_data.DisplaySize)
    glOrtho(disp_pos.x, disp_pos.x + disp_size.x, disp_pos.y + disp_size.y, disp_pos.y, -1f0, +1f0)
    glMatrixMode(GL_MODELVIEW)
    glPushMatrix()
    glLoadIdentity()
end

# OpenGL2 Render function.
# Note that this implementation is little overcomplicated because we are saving/setting up/restoring every OpenGL state explicitly.
# This is in order to be able to run within an OpenGL engine that doesn't do so.
function ImGui_ImplOpenGL2_RenderDrawData(ctx::Context, draw_data)
    # Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fb_width = trunc(Cint, unsafe_load(draw_data.DisplaySize.x) * unsafe_load(draw_data.FramebufferScale.x))
    fb_height = trunc(Cint, unsafe_load(draw_data.DisplaySize.y) * unsafe_load(draw_data.FramebufferScale.y))
    (fb_width == 0 || fb_height == 0) && return nothing

    # Backup GL state
    last_texture = GLint(0); @c glGetIntegerv(GL_TEXTURE_BINDING_2D, &last_texture)
    last_polygon_mode = GLint[0,0]; glGetIntegerv(GL_POLYGON_MODE, last_polygon_mode)
    last_viewport = GLint[0,0,0,0]; glGetIntegerv(GL_VIEWPORT, last_viewport)
    last_scissor_box = GLint[0,0,0,0]; glGetIntegerv(GL_SCISSOR_BOX, last_scissor_box)
    last_shade_model = GLint(0); @c glGetIntegerv(GL_SHADE_MODEL, &last_shade_model)
    last_tex_env_mode = GLint(0); @c glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &last_tex_env_mode)
    glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT | GL_TRANSFORM_BIT)

    # Setup desired GL state
    ImGui_ImplOpenGL2_SetupRenderState(ctx, draw_data, fb_width, fb_height)

    # Will project scissor/clipping rectangles into framebuffer space
    clip_off = unsafe_load(draw_data.DisplayPos)         # (0,0) unless using multi-viewports
    clip_scale = unsafe_load(draw_data.FramebufferScale) # (1,1) unless using retina display which are often (2,2)

    # Render command lists
    data = unsafe_load(draw_data)
    cmd_lists = unsafe_wrap(Vector{Ptr{ImDrawList}}, data.CmdLists, data.CmdListsCount)
    for cmd_list in cmd_lists
        vtx_buffer = unsafe_load(cmd_list.VtxBuffer).Data
        idx_buffer_offset = Csize_t(unsafe_load(cmd_list.IdxBuffer).Data)

        glVertexPointer(2, GL_FLOAT, sizeof(ImDrawVert), vtx_buffer + offsetof(ImDrawVert, Val(:pos)))
        glTexCoordPointer(2, GL_FLOAT, sizeof(ImDrawVert), vtx_buffer + offsetof(ImDrawVert, Val(:uv)))
        glColorPointer(4, GL_UNSIGNED_BYTE, sizeof(ImDrawVert), vtx_buffer + offsetof(ImDrawVert, Val(:col)))

        cmd_buffer = cmd_list.CmdBuffer |> unsafe_load
        for cmd_i = 0:(cmd_buffer.Size-1)
            pcmd = cmd_buffer.Data + cmd_i * sizeof(ImDrawCmd)
            cb_funcptr = unsafe_load(pcmd.UserCallback)
            elem_count = unsafe_load(pcmd.ElemCount)
            if cb_funcptr != C_NULL
                # User callback, registered via ImDrawList::AddCallback()
                # (ImDrawCallback_ResetRenderState is a special callback value used by the user to request the renderer to reset render state.)
                if cb_funcptr == ctx.ImDrawCallback_ResetRenderState
                    ImGui_ImplOpenGL2_SetupRenderState(draw_data, fb_width, fb_height)
                else
                    ccall(cb_funcptr, Cvoid, (Ptr{ImDrawList}, Ptr{ImDrawCmd}), cmd_list, pcmd)
                end
            else
                # project scissor/clipping rectangles into framebuffer space
                rect = unsafe_load(pcmd.ClipRect)
                clip_rect_x = (rect.x - clip_off.x) * clip_scale.x
                clip_rect_y = (rect.y - clip_off.y) * clip_scale.y
                clip_rect_z = (rect.z - clip_off.x) * clip_scale.x
                clip_rect_w = (rect.w - clip_off.y) * clip_scale.y
                if clip_rect_x < fb_width && clip_rect_y < fb_height && clip_rect_z ≥ 0 && clip_rect_w ≥ 0
                    # apply scissor/clipping rectangle
                    ix = trunc(Cint, clip_rect_x)
                    iy = trunc(Cint, fb_height - clip_rect_w)
                    iz = trunc(Cint, clip_rect_z - clip_rect_x)
                    iw = trunc(Cint, clip_rect_w - clip_rect_y)
                    glScissor(ix, iy, iz, iw)
                    # Bind texture, Draw
                    glBindTexture(GL_TEXTURE_2D, UInt(unsafe_load(pcmd.TextureId)))
                    glDrawElements(GL_TRIANGLES, GLsizei(elem_count), GL_UNSIGNED_SHORT, Ptr{Cvoid}(idx_buffer_offset))
                end
            end
            idx_buffer_offset += elem_count * sizeof(ImDrawIdx)
        end
    end

    # Restore modified GL state
    glDisableClientState(GL_COLOR_ARRAY)
    glDisableClientState(GL_TEXTURE_COORD_ARRAY)
    glDisableClientState(GL_VERTEX_ARRAY)
    glBindTexture(GL_TEXTURE_2D, last_texture)
    glMatrixMode(GL_MODELVIEW)
    glPopMatrix()
    glMatrixMode(GL_PROJECTION)
    glPopMatrix()
    glPopAttrib()
    glPolygonMode(GL_FRONT, last_polygon_mode[1]); glPolygonMode(GL_BACK, last_polygon_mode[2])
    glViewport(last_viewport...)
    glScissor(last_scissor_box...)
    glShadeModel(last_shade_model)
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, last_tex_env_mode)
end

@generated function offsetof(::Type{X}, ::Val{field}) where {X,field}
    idx = findfirst(f->f==field, fieldnames(X))
    return fieldoffset(X, idx)
end
