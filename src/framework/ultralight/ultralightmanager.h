#pragma once

#include <framework/graphics/declarations.h>

#include <map>
#include <string>

#ifndef OTCLIENT_HAS_ULTRALIGHT
#if __has_include(<Ultralight/Ultralight.h>)
#define OTCLIENT_HAS_ULTRALIGHT 1
#else
#define OTCLIENT_HAS_ULTRALIGHT 0
#endif
#endif

#if OTCLIENT_HAS_ULTRALIGHT
#include <Ultralight/Ultralight.h>
#include <AppCore/Platform.h>
#endif

class Painter;

#if OTCLIENT_HAS_ULTRALIGHT

class UltraLightManager
{
public:
    UltraLightManager() = default;
    ~UltraLightManager();

    bool initialize();
    void shutdown();
    bool isInitialized() const { return m_initialized; }

    void createView(const std::string& name, int width, int height, const std::string& htmlPath);
    void removeView(const std::string& name);
    bool hasView(const std::string& name) const;
    void resizeView(const std::string& name, int width, int height);

    void loadURL(const std::string& name, const std::string& url);
    void loadFile(const std::string& name, const std::string& path);
    void reload(const std::string& name);

    void setViewVisible(const std::string& name, bool visible);
    bool isViewVisible(const std::string& name) const;
    void setViewPosition(const std::string& name, int x, int y);
    void setViewFocus(const std::string& name, bool focused);
    void setViewSize(const std::string& name, int width, int height);

    int getViewWidth(const std::string& name) const;
    int getViewHeight(const std::string& name) const;
    std::vector<std::string> getViewNames() const;

    void callJSFunction(const std::string& viewName, const std::string& functionName, const std::string& argsJson);
    void executeJavaScript(const std::string& viewName, const std::string& code);

    bool handleInputEvent(const struct InputEvent& event);
    void update();
    void render(Painter& painter);

    std::string getItemSpriteDataUri(uint32_t itemId);
    TexturePtr getViewTexture(const std::string& name) const;

    void dispatchLuaFunction(const std::string& functionPath, const std::vector<std::string>& args);

private:
    struct ViewData {
        ultralight::RefPtr<ultralight::View> view;
        TexturePtr texture;
        int x = 0;
        int y = 0;
        bool visible = true;
        bool focused = false;
        std::shared_ptr<class UltraViewListener> listener;
    };

    std::string detectUltralightBaseDir();
    void setupJSBindings(ultralight::View* view);
    void uploadViewSurface(ViewData& data);
    ultralight::MouseEvent::Button toUltralightMouseButton(uint8_t otcButton) const;
    int toUltralightVirtualKeyCode(uint8_t otcKey) const;
    ViewData* findViewAtPoint(int x, int y);

    bool m_initialized = false;
    ultralight::RefPtr<ultralight::Renderer> m_renderer;
    std::map<std::string, ViewData> m_views;
    std::string m_focusedViewName;
};

extern UltraLightManager g_ultralightManager;

#else

class UltraLightManager
{
public:
    bool initialize() { return false; }
    void shutdown() {}
    bool isInitialized() const { return false; }
    void createView(const std::string&, int, int, const std::string&) {}
    void removeView(const std::string&) {}
    bool hasView(const std::string&) const { return false; }
    void resizeView(const std::string&, int, int) {}
    void loadURL(const std::string&, const std::string&) {}
    void loadFile(const std::string&, const std::string&) {}
    void reload(const std::string&) {}
    void setViewVisible(const std::string&, bool) {}
    bool isViewVisible(const std::string&) const { return false; }
    void setViewPosition(const std::string&, int, int) {}
    void setViewFocus(const std::string&, bool) {}
    void setViewSize(const std::string&, int, int) {}
    int getViewWidth(const std::string&) const { return 0; }
    int getViewHeight(const std::string&) const { return 0; }
    std::vector<std::string> getViewNames() const { return {}; }
    void callJSFunction(const std::string&, const std::string&, const std::string&) {}
    void executeJavaScript(const std::string&, const std::string&) {}
    bool handleInputEvent(const struct InputEvent&) { return false; }
    void update() {}
    void render(Painter&) {}
    std::string getItemSpriteDataUri(uint32_t) { return ""; }
    TexturePtr getViewTexture(const std::string&) const { return nullptr; }
};

extern UltraLightManager g_ultralightManager;

#endif
