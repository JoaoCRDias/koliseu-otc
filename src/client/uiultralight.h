#pragma once

#include <framework/ui/uiwidget.h>

#if OTCLIENT_HAS_ULTRALIGHT
#include <framework/ultralight/ultralightmanager.h>
#endif

class UIUltralight final : public UIWidget
{
public:
    UIUltralight();
    ~UIUltralight() override;

    void drawSelf(DrawPoolType drawPane) override;

    void setSource(const std::string& url);
    std::string getSource() const { return m_source; }

    void callJSFunction(const std::string& functionName, const std::string& argsJson);
    void executeJavaScript(const std::string& code);

    void onStyleApply(std::string_view styleName, const OTMLNodePtr& styleNode) override;
    void onGeometryChange(const Rect& oldRect, const Rect& newRect) override;
    void onVisibilityChange(bool visible) override;

protected:
    bool onMousePress(const Point& mousePos, Fw::MouseButton button) override;
    bool onMouseRelease(const Point& mousePos, Fw::MouseButton button) override;
    bool onMouseMove(const Point& mousePos, const Point& mouseMoved) override;
    bool onMouseWheel(const Point& mousePos, Fw::MouseWheelDirection direction) override;
    bool onKeyPress(uint8_t keyCode, int keyboardModifiers, int autoRepeatTicks) override;

private:
    void ensureView();
    std::string m_source;
    std::string m_viewId;
    bool m_needsResize = false;
};
