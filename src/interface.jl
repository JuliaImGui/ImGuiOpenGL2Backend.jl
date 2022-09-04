#----------------------------------------
# OpenGL    GLSL      GLSL
# version   version   string
#----------------------------------------
#  2.0       110       "#version 110"
#  2.1       120
#  3.0       130
#  3.1       140
#  3.2       150       "#version 150"
#  3.3       330
#  4.0       400
#  4.1       410       "#version 410 core"
#  4.2       420
#  4.3       430
#  ES 2.0    100       "#version 100"
#  ES 3.0    300       "#version 300 es"
#----------------------------------------

const IMGUI_BACKEND_RENDERER_NAME = "imgui_impl_opengl2"

function init(ctx::Context)
    io::Ptr{ImGuiIO} = igGetIO()
    io.BackendRendererName = pointer(IMGUI_BACKEND_RENDERER_NAME)
    io.BackendFlags = unsafe_load(io.BackendFlags) & ~(ImGuiBackendFlags_RendererHasVtxOffset)  # version ≥ 320
    io.BackendFlags = unsafe_load(io.BackendFlags) | ImGuiBackendFlags_RendererHasViewports

    if unsafe_load(io.ConfigFlags) & ImGuiConfigFlags_ViewportsEnable == ImGuiConfigFlags_ViewportsEnable
        ImGui_ImplOpenGL2_InitPlatformInterface()
    end

    return true
end

function shutdown(ctx::Context)
    ImGui_ImplOpenGL2_ShutdownPlatformInterface()
    ImGui_ImplOpenGL2_DestroyDeviceObjects(ctx)
    return true
end

function new_frame(ctx::Context)
    if ctx.FontTexture == 0
        ImGui_ImplOpenGL2_CreateDeviceObjects(ctx)
    end
    return true
end

render(ctx::Context) = ImGui_ImplOpenGL2_RenderDrawData(ctx, igGetDrawData())
