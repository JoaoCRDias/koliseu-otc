#include "ultralightmanager.h"

#if OTCLIENT_HAS_ULTRALIGHT

#include <Ultralight/Ultralight.h>
#include <AppCore/Platform.h>
#include <Ultralight/Bitmap.h>
#include <Ultralight/platform/Surface.h>
#include <Ultralight/KeyEvent.h>
#include <Ultralight/MouseEvent.h>
#include <Ultralight/ScrollEvent.h>
#include <framework/core/inputevent.h>
#include <framework/graphics/coordsbuffer.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/image.h>
#include <framework/graphics/painter.h>
#include <framework/graphics/texture.h>
#include <framework/luaengine/luainterface.h>
#include <framework/util/crypt.h>
#include <client/spritemanager.h>
#include <filesystem>
#include <fstream>
#include <algorithm>
#include <sstream>

UltraLightManager g_ultralightManager;

class UltraViewListener : public ultralight::ViewListener
{
public:
    UltraViewListener(UltraLightManager* manager) : m_manager(manager) {}

    void OnChangeTitle(ultralight::View* caller, const ultralight::String& title) override
    {
        std::string titleStr = title.utf8().data();
        const std::string prefix = "__otc_lua__";
        if (titleStr.size() > prefix.size() && titleStr.substr(0, prefix.size()) == prefix) {
            std::string payload = titleStr.substr(prefix.size());
            std::vector<std::string> parts;
            std::stringstream ss(payload);
            std::string part;
            while (std::getline(ss, part, '|')) {
                parts.push_back(part);
            }
            if (!parts.empty()) {
                std::string functionPath = parts[0];
                parts.erase(parts.begin());
                for (auto& arg : parts) {
                    std::string decoded;
                    for (size_t i = 0; i < arg.size(); ++i) {
                        if (arg[i] == '%' && i + 2 < arg.size()) {
                            char hex[3] = { arg[i + 1], arg[i + 2], 0 };
                            decoded += static_cast<char>(strtol(hex, nullptr, 16));
                            i += 2;
                        } else {
                            decoded += arg[i];
                        }
                    }
                    arg = decoded;
                }
                m_manager->dispatchLuaFunction(functionPath, parts);
            }
        }
    }

    void OnChangeCursor(ultralight::View* caller, ultralight::Cursor cursor) override {}

    void OnAddConsoleMessage(ultralight::View* caller, const ultralight::ConsoleMessage& msg) override {}

private:
    UltraLightManager* m_manager;
};

static const char* JS_BRIDGE_CODE = R"(
window.callLuaFunction = function(functionPath /*, arg1, arg2, ... */) {
    var payload = functionPath;
    for (var i = 1; i < arguments.length; i++) {
        payload += '|' + encodeURIComponent(String(arguments[i]));
    }
    document.title = '__otc_lua__' + payload;
    return true;
};
)";

UltraLightManager::~UltraLightManager()
{
    shutdown();
}

std::string UltraLightManager::detectUltralightBaseDir()
{
    namespace fs = std::filesystem;

    auto checkDir = [](const fs::path& base) -> std::string {
        fs::path resPath = base / "resources";
        if (fs::exists(resPath / "cacert.pem") || fs::exists(resPath)) {
            return base.string();
        }
        return {};
    };

    std::error_code ec;
    fs::path exePath = fs::current_path(ec);
    if (!ec) {
        std::string result = checkDir(exePath);
        if (!result.empty()) return result;
        result = checkDir(exePath.parent_path());
        if (!result.empty()) return result;
    }

    return {};
}

bool UltraLightManager::initialize()
{
    if (m_initialized) return true;

    ultralight::Config config;

    std::string baseDir = detectUltralightBaseDir();
    if (!baseDir.empty()) {
        config.resource_path_prefix = ultralight::String((baseDir + "/resources/").c_str());
        config.cache_path = ultralight::String((baseDir + "/cache/ultralight").c_str());
    }

    auto& platform = ultralight::Platform::instance();
    platform.set_config(config);
    platform.set_font_loader(ultralight::GetPlatformFontLoader());
    platform.set_file_system(ultralight::GetPlatformFileSystem(baseDir.empty() ? "." : baseDir.c_str()));
    platform.set_logger(ultralight::GetDefaultLogger("ultralight.log"));

    m_renderer = ultralight::Renderer::Create();
    if (!m_renderer) return false;

    m_initialized = true;
    return true;
}

void UltraLightManager::shutdown()
{
    if (!m_initialized) return;

    m_views.clear();
    m_renderer = nullptr;
    m_initialized = false;
}

void UltraLightManager::createView(const std::string& name, int width, int height, const std::string& htmlPath)
{
    if (!m_initialized) return;

    removeView(name);

    ultralight::ViewConfig viewConfig;
    viewConfig.is_accelerated = false;
    viewConfig.is_transparent = true;

    auto view = m_renderer->CreateView(width, height, viewConfig, nullptr);
    if (!view) return;

    ViewData data;
    data.view = view;
    data.texture = std::make_shared<Texture>(Size(width, height));
    data.x = 0;
    data.y = 0;
    data.visible = true;
    data.focused = false;

    data.listener = std::make_shared<UltraViewListener>(this);
    view->set_view_listener(data.listener.get());

    setupJSBindings(view.get());

    if (!htmlPath.empty()) {
        loadFile(name, htmlPath);
    }

    m_views[name] = std::move(data);
}

void UltraLightManager::removeView(const std::string& name)
{
    auto it = m_views.find(name);
    if (it != m_views.end()) {
        if (m_focusedViewName == name) {
            m_focusedViewName.clear();
        }
        m_views.erase(it);
    }
}

bool UltraLightManager::hasView(const std::string& name) const
{
    return m_views.find(name) != m_views.end();
}

void UltraLightManager::resizeView(const std::string& name, int width, int height)
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return;

    auto& data = it->second;
    data.view->Resize(width, height);
    data.texture = std::make_shared<Texture>(Size(width, height));
}

void UltraLightManager::loadURL(const std::string& name, const std::string& url)
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return;
    it->second.view->LoadURL(ultralight::String(url.c_str()));
}

void UltraLightManager::loadFile(const std::string& name, const std::string& path)
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return;

    std::string url = "file:///" + path;
    if (path.find("://") != std::string::npos) {
        url = path;
    }
    it->second.view->LoadURL(ultralight::String(url.c_str()));
}

void UltraLightManager::reload(const std::string& name)
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return;
    it->second.view->Reload();
}

void UltraLightManager::setViewVisible(const std::string& name, bool visible)
{
    auto it = m_views.find(name);
    if (it != m_views.end()) {
        it->second.visible = visible;
        if (!visible && m_focusedViewName == name) {
            m_focusedViewName.clear();
            it->second.focused = false;
        }
    }
}

bool UltraLightManager::isViewVisible(const std::string& name) const
{
    auto it = m_views.find(name);
    return it != m_views.end() && it->second.visible;
}

void UltraLightManager::setViewPosition(const std::string& name, int x, int y)
{
    auto it = m_views.find(name);
    if (it != m_views.end()) {
        it->second.x = x;
        it->second.y = y;
    }
}

void UltraLightManager::setViewFocus(const std::string& name, bool focused)
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return;

    if (focused) {
        if (!m_focusedViewName.empty() && m_focusedViewName != name) {
            auto prev = m_views.find(m_focusedViewName);
            if (prev != m_views.end()) {
                prev->second.focused = false;
            }
        }
        m_focusedViewName = name;
        it->second.focused = true;
        it->second.view->Focus();
    } else {
        if (m_focusedViewName == name) {
            m_focusedViewName.clear();
        }
        it->second.focused = false;
        it->second.view->Unfocus();
    }
}

void UltraLightManager::setViewSize(const std::string& name, int width, int height)
{
    resizeView(name, width, height);
}

int UltraLightManager::getViewWidth(const std::string& name) const
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return 0;
    return static_cast<int>(it->second.view->width());
}

int UltraLightManager::getViewHeight(const std::string& name) const
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return 0;
    return static_cast<int>(it->second.view->height());
}

std::vector<std::string> UltraLightManager::getViewNames() const
{
    std::vector<std::string> names;
    for (const auto& [name, data] : m_views) {
        names.push_back(name);
    }
    return names;
}

void UltraLightManager::callJSFunction(const std::string& viewName, const std::string& functionName, const std::string& argsJson)
{
    auto it = m_views.find(viewName);
    if (it == m_views.end()) return;

    std::string script = functionName + "(" + argsJson + ");";
    it->second.view->EvaluateScript(ultralight::String(script.c_str()));
}

void UltraLightManager::executeJavaScript(const std::string& viewName, const std::string& code)
{
    auto it = m_views.find(viewName);
    if (it == m_views.end()) return;
    it->second.view->EvaluateScript(ultralight::String(code.c_str()));
}

void UltraLightManager::setupJSBindings(ultralight::View* view)
{
    view->EvaluateScript(ultralight::String(JS_BRIDGE_CODE));
}

void UltraLightManager::dispatchLuaFunction(const std::string& functionPath, const std::vector<std::string>& args)
{
    size_t dotPos = functionPath.find('.');
    if (dotPos == std::string::npos) return;

    std::string global = functionPath.substr(0, dotPos);
    std::string field = functionPath.substr(dotPos + 1);

    g_lua.getGlobalField(global, field);
    if (!g_lua.isFunction()) {
        g_lua.pop(1);
        return;
    }

    for (const auto& arg : args) {
        g_lua.pushString(arg);
    }
    g_lua.signalCall(static_cast<int>(args.size()));
    g_lua.pop();
}

void UltraLightManager::update()
{
    if (!m_initialized || !m_renderer) return;
    m_renderer->Update();
}

void UltraLightManager::uploadViewSurface(ViewData& data)
{
    auto* surface = static_cast<ultralight::BitmapSurface*>(data.view->surface());
    if (!surface) return;

    auto bitmap = surface->bitmap();
    if (!bitmap) return;

    ultralight::IntRect bounds = surface->dirty_bounds();
    if (bounds.left >= bounds.right || bounds.top >= bounds.bottom) return;

    void* pixels = bitmap->LockPixels();
    if (!pixels) return;

    auto width = static_cast<int>(bitmap->width());
    auto height = static_cast<int>(bitmap->height());
    auto rowBytes = bitmap->row_bytes();

    if (!data.texture || data.texture->getSize() != Size(width, height)) {
        bitmap->UnlockPixels();
        surface->ClearDirtyBounds();
        return;
    }

    std::vector<uint8_t> rgbaPixels(width * height * 4);
    auto* src = static_cast<uint8_t*>(pixels);

    for (int y = 0; y < static_cast<int>(height); ++y) {
        for (int x = 0; x < static_cast<int>(width); ++x) {
            auto* srcPixel = src + y * rowBytes + x * 4;
            auto* dstPixel = rgbaPixels.data() + (y * width + x) * 4;

            dstPixel[0] = srcPixel[2]; // B -> R
            dstPixel[1] = srcPixel[1]; // G -> G
            dstPixel[2] = srcPixel[0]; // R -> B
            dstPixel[3] = srcPixel[3]; // A -> A

            if (dstPixel[3] == 0 && (dstPixel[0] != 0 || dstPixel[1] != 0 || dstPixel[2] != 0)) {
                dstPixel[3] = 255;
            }
        }
    }

    bitmap->UnlockPixels();
    surface->ClearDirtyBounds();

    data.texture->updatePixels(rgbaPixels.data(), 0, 4, false);
}

void UltraLightManager::render(Painter& painter)
{
    if (!m_initialized) return;

    m_renderer->Render();

    painter.resetClipRect();
    painter.resetTransformMatrix();
    painter.resetCompositionMode();
    painter.resetOpacity();
    painter.resetColor();

    for (auto& [name, data] : m_views) {
        if (!data.visible) continue;

        uploadViewSurface(data);
        if (!data.texture) continue;

        int w = data.texture->getWidth();
        int h = data.texture->getHeight();

        CoordsBuffer coords;
        coords.addRect(RectF(data.x, data.y + h, data.x + w, data.y),
            RectF(0.0f, 0.0f, static_cast<float>(w), static_cast<float>(h)));
        painter.setTexture(data.texture);
        painter.drawCoords(coords);
    }

    painter.resetTexture();
}

bool UltraLightManager::handleInputEvent(const InputEvent& event)
{
    if (!m_initialized) return false;

    using namespace Fw;

    switch (event.type) {
    case MousePressInputEvent: {
        for (auto& [name, data] : m_views) {
            if (!data.visible) continue;
            int vw = static_cast<int>(data.view->width());
            int vh = static_cast<int>(data.view->height());
            if (event.mousePos.x >= data.x && event.mousePos.x < data.x + vw &&
                event.mousePos.y >= data.y && event.mousePos.y < data.y + vh) {
                ultralight::MouseEvent me;
                me.type = ultralight::MouseEvent::kType_MouseDown;
                me.button = toUltralightMouseButton(event.mouseButton);
                me.x = event.mousePos.x - data.x;
                me.y = event.mousePos.y - data.y;
                data.view->FireMouseEvent(me);
                setViewFocus(name, true);
                return true;
            }
        }
        return false;
    }

    case MouseReleaseInputEvent: {
        for (auto& [name, data] : m_views) {
            if (!data.visible) continue;
            int vw = static_cast<int>(data.view->width());
            int vh = static_cast<int>(data.view->height());
            if (event.mousePos.x >= data.x && event.mousePos.x < data.x + vw &&
                event.mousePos.y >= data.y && event.mousePos.y < data.y + vh) {
                ultralight::MouseEvent me;
                me.type = ultralight::MouseEvent::kType_MouseUp;
                me.button = toUltralightMouseButton(event.mouseButton);
                me.x = event.mousePos.x - data.x;
                me.y = event.mousePos.y - data.y;
                data.view->FireMouseEvent(me);
                return true;
            }
        }
        return false;
    }

    case MouseMoveInputEvent: {
        for (auto& [name, data] : m_views) {
            if (!data.visible) continue;
            int vw = static_cast<int>(data.view->width());
            int vh = static_cast<int>(data.view->height());
            if (event.mousePos.x >= data.x && event.mousePos.x < data.x + vw &&
                event.mousePos.y >= data.y && event.mousePos.y < data.y + vh) {
                ultralight::MouseEvent me;
                me.type = ultralight::MouseEvent::kType_MouseMoved;
                me.button = ultralight::MouseEvent::kButton_None;
                me.x = event.mousePos.x - data.x;
                me.y = event.mousePos.y - data.y;
                data.view->FireMouseEvent(me);
                return true;
            }
        }
        return false;
    }

    case MouseWheelInputEvent: {
        for (auto& [name, data] : m_views) {
            if (!data.visible) continue;
            int vw = static_cast<int>(data.view->width());
            int vh = static_cast<int>(data.view->height());
            if (event.mousePos.x >= data.x && event.mousePos.x < data.x + vw &&
                event.mousePos.y >= data.y && event.mousePos.y < data.y + vh) {
                ultralight::ScrollEvent se;
                se.type = ultralight::ScrollEvent::kType_ScrollByPixel;
                se.delta_x = 0;
                se.delta_y = (event.wheelDirection == MouseWheelUp) ? 30 : -30;
                data.view->FireScrollEvent(se);
                return true;
            }
        }
        return false;
    }

    case KeyPressInputEvent:
    case KeyDownInputEvent: {
        if (m_focusedViewName.empty()) return false;
        auto it = m_views.find(m_focusedViewName);
        if (it == m_views.end()) return false;
        if (!it->second.visible || !it->second.focused) return false;

        ultralight::KeyEvent evt;
        evt.type = ultralight::KeyEvent::kType_RawKeyDown;
        evt.virtual_key_code = toUltralightVirtualKeyCode(event.keyCode);
        evt.native_key_code = 0;
        evt.modifiers = 0;
        if (event.keyboardModifiers & KeyboardCtrlModifier) evt.modifiers |= ultralight::KeyEvent::kMod_CtrlKey;
        if (event.keyboardModifiers & KeyboardAltModifier) evt.modifiers |= ultralight::KeyEvent::kMod_AltKey;
        if (event.keyboardModifiers & KeyboardShiftModifier) evt.modifiers |= ultralight::KeyEvent::kMod_ShiftKey;
        ultralight::String keyText(event.keyText.empty() ? "" : event.keyText.c_str());
        evt.text = keyText;
        evt.unmodified_text = keyText;
        it->second.view->FireKeyEvent(evt);

        if (!event.keyText.empty()) {
            ultralight::KeyEvent charEvt;
            charEvt.type = ultralight::KeyEvent::kType_Char;
            charEvt.virtual_key_code = toUltralightVirtualKeyCode(event.keyCode);
            charEvt.native_key_code = 0;
            charEvt.modifiers = evt.modifiers;
            charEvt.text = keyText;
            charEvt.unmodified_text = keyText;
            it->second.view->FireKeyEvent(charEvt);
        }
        return true;
    }

    case KeyUpInputEvent: {
        if (m_focusedViewName.empty()) return false;
        auto it = m_views.find(m_focusedViewName);
        if (it == m_views.end()) return false;
        if (!it->second.visible || !it->second.focused) return false;

        ultralight::KeyEvent evt;
        evt.type = ultralight::KeyEvent::kType_KeyUp;
        evt.virtual_key_code = toUltralightVirtualKeyCode(event.keyCode);
        evt.native_key_code = 0;
        evt.modifiers = 0;
        if (event.keyboardModifiers & KeyboardCtrlModifier) evt.modifiers |= ultralight::KeyEvent::kMod_CtrlKey;
        if (event.keyboardModifiers & KeyboardAltModifier) evt.modifiers |= ultralight::KeyEvent::kMod_AltKey;
        if (event.keyboardModifiers & KeyboardShiftModifier) evt.modifiers |= ultralight::KeyEvent::kMod_ShiftKey;
        ultralight::String keyText(event.keyText.empty() ? "" : event.keyText.c_str());
        evt.text = keyText;
        evt.unmodified_text = keyText;
        it->second.view->FireKeyEvent(evt);
        return true;
    }

    default:
        return false;
    }
}

std::string UltraLightManager::getItemSpriteDataUri(uint32_t itemId)
{
    bool isLoading = false;
    auto image = g_sprites.getSpriteImage(itemId, isLoading);
    if (!image) return "";

    int w = image->getWidth();
    int h = image->getHeight();
    int bpp = image->getBpp();
    auto* pixels = image->getPixelData();

    if (!pixels || w <= 0 || h <= 0) return "";

    std::vector<uint8_t> rgbaData(w * h * 4);
    if (bpp == 4) {
        memcpy(rgbaData.data(), pixels, w * h * 4);
    } else if (bpp == 3) {
        for (int i = 0; i < w * h; ++i) {
            rgbaData[i * 4 + 0] = pixels[i * 3 + 0];
            rgbaData[i * 4 + 1] = pixels[i * 3 + 1];
            rgbaData[i * 4 + 2] = pixels[i * 3 + 2];
            rgbaData[i * 4 + 3] = 255;
        }
    }

    Image rgbaImage(Size(w, h), 4, rgbaData.data());
    std::string tmpFile = "tmp_sprite_" + std::to_string(itemId) + ".png";
    rgbaImage.savePNG(tmpFile);

    std::ifstream file(tmpFile, std::ios::binary);
    if (!file.is_open()) return "";
    std::vector<uint8_t> fileData((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    file.close();

    std::string rawStr(fileData.begin(), fileData.end());
    std::string base64 = g_crypt.base64Encode(rawStr);

    std::filesystem::remove(tmpFile);

    return "data:image/png;base64," + base64;
}

UltraLightManager::ViewData* UltraLightManager::findViewAtPoint(int x, int y)
{
    for (auto& [name, data] : m_views) {
        if (!data.visible) continue;
        int vw = static_cast<int>(data.view->width());
        int vh = static_cast<int>(data.view->height());
        if (x >= data.x && x < data.x + vw && y >= data.y && y < data.y + vh) {
            return &data;
        }
    }
    return nullptr;
}

TexturePtr UltraLightManager::getViewTexture(const std::string& name) const
{
    auto it = m_views.find(name);
    if (it == m_views.end()) return nullptr;
    return it->second.texture;
}

ultralight::MouseEvent::Button UltraLightManager::toUltralightMouseButton(uint8_t otcButton) const
{
    switch (otcButton) {
    case Fw::MouseLeftButton: return ultralight::MouseEvent::kButton_Left;
    case Fw::MouseRightButton: return ultralight::MouseEvent::kButton_Right;
    case Fw::MouseMidButton: return ultralight::MouseEvent::kButton_Middle;
    default: return ultralight::MouseEvent::kButton_None;
    }
}

int UltraLightManager::toUltralightVirtualKeyCode(uint8_t otcKey) const
{
    if (otcKey >= 'A' && otcKey <= 'Z') return otcKey;
    if (otcKey >= '0' && otcKey <= '9') return otcKey;

    switch (otcKey) {
    case 0x08: return ultralight::KeyCodes::GK_BACK;
    case 0x09: return ultralight::KeyCodes::GK_TAB;
    case 0x0D: return ultralight::KeyCodes::GK_RETURN;
    case 0x1B: return ultralight::KeyCodes::GK_ESCAPE;
    case 0x20: return ultralight::KeyCodes::GK_SPACE;
    case 0x2D: return ultralight::KeyCodes::GK_INSERT;
    case 0x2E: return ultralight::KeyCodes::GK_DELETE;
    case 0x21: return ultralight::KeyCodes::GK_PRIOR;
    case 0x22: return ultralight::KeyCodes::GK_NEXT;
    case 0x23: return ultralight::KeyCodes::GK_END;
    case 0x24: return ultralight::KeyCodes::GK_HOME;
    case 0x25: return ultralight::KeyCodes::GK_LEFT;
    case 0x26: return ultralight::KeyCodes::GK_UP;
    case 0x27: return ultralight::KeyCodes::GK_RIGHT;
    case 0x28: return ultralight::KeyCodes::GK_DOWN;
    case 0x70: return ultralight::KeyCodes::GK_F1;
    case 0x71: return ultralight::KeyCodes::GK_F2;
    case 0x72: return ultralight::KeyCodes::GK_F3;
    case 0x73: return ultralight::KeyCodes::GK_F4;
    case 0x74: return ultralight::KeyCodes::GK_F5;
    case 0x75: return ultralight::KeyCodes::GK_F6;
    case 0x76: return ultralight::KeyCodes::GK_F7;
    case 0x77: return ultralight::KeyCodes::GK_F8;
    case 0x78: return ultralight::KeyCodes::GK_F9;
    case 0x79: return ultralight::KeyCodes::GK_F10;
    case 0x7A: return ultralight::KeyCodes::GK_F11;
    case 0x7B: return ultralight::KeyCodes::GK_F12;
    default: return otcKey;
    }
}

#else

UltraLightManager g_ultralightManager;

#endif
