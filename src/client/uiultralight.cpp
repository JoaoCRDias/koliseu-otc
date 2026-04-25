#include "uiultralight.h"
#include <framework/graphics/drawpoolmanager.h>
#include <framework/ultralight/ultralightmanager.h>
#include <framework/otml/otmlnode.h>

static int s_viewCounter = 0;

UIUltralight::UIUltralight()
{
    s_viewCounter++;
    m_viewId = "ultralight_widget_" + std::to_string(s_viewCounter);
}

UIUltralight::~UIUltralight()
{
    if (g_ultralightManager.isInitialized()) {
        g_ultralightManager.removeView(m_viewId);
    }
}

void UIUltralight::ensureView()
{
#if OTCLIENT_HAS_ULTRALIGHT
    if (!g_ultralightManager.isInitialized()) {
        g_ultralightManager.initialize();
    }

    if (!g_ultralightManager.hasView(m_viewId)) {
        int w = std::max(getWidth(), 1);
        int h = std::max(getHeight(), 1);
        g_ultralightManager.createView(m_viewId, w, h, m_source);

        if (!m_source.empty() && m_source.find("://") == std::string::npos && m_source.find("<") == std::string::npos) {
            g_ultralightManager.loadFile(m_viewId, m_source);
        }
    }

    if (m_needsResize) {
        int w = std::max(getWidth(), 1);
        int h = std::max(getHeight(), 1);
        g_ultralightManager.resizeView(m_viewId, w, h);
        m_needsResize = false;
    }
#endif
}

void UIUltralight::drawSelf(DrawPoolType drawPane)
{
    if (drawPane != DrawPoolType::FOREGROUND)
        return;

#if OTCLIENT_HAS_ULTRALIGHT
    if (!isVisible())
        return;

    ensureView();

    g_ultralightManager.setViewVisible(m_viewId, true);
    g_ultralightManager.setViewPosition(m_viewId, m_rect.x(), m_rect.y());

    auto texture = g_ultralightManager.getViewTexture(m_viewId);
    if (texture) {
        g_drawPool.addTexturedRect(m_rect, texture, Color::white);
    }
#endif
}

void UIUltralight::setSource(const std::string& url)
{
    m_source = url;
#if OTCLIENT_HAS_ULTRALIGHT
    if (g_ultralightManager.hasView(m_viewId)) {
        if (url.find("://") != std::string::npos) {
            g_ultralightManager.loadURL(m_viewId, url);
        } else {
            g_ultralightManager.loadFile(m_viewId, url);
        }
    }
#endif
}

void UIUltralight::callJSFunction(const std::string& functionName, const std::string& argsJson)
{
#if OTCLIENT_HAS_ULTRALIGHT
    g_ultralightManager.callJSFunction(m_viewId, functionName, argsJson);
#endif
}

void UIUltralight::executeJavaScript(const std::string& code)
{
#if OTCLIENT_HAS_ULTRALIGHT
    g_ultralightManager.executeJavaScript(m_viewId, code);
#endif
}

void UIUltralight::onStyleApply(std::string_view styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    for (const OTMLNodePtr& node : styleNode->children()) {
        if (node->tag() == "source")
            setSource(node->value());
    }
}

void UIUltralight::onGeometryChange(const Rect& oldRect, const Rect& newRect)
{
    UIWidget::onGeometryChange(oldRect, newRect);
    m_needsResize = true;
}

void UIUltralight::onVisibilityChange(bool visible)
{
    UIWidget::onVisibilityChange(visible);
#if OTCLIENT_HAS_ULTRALIGHT
    g_ultralightManager.setViewVisible(m_viewId, visible);
#endif
}

bool UIUltralight::onMousePress(const Point& mousePos, Fw::MouseButton button)
{
#if OTCLIENT_HAS_ULTRALIGHT
    if (g_ultralightManager.isInitialized() && g_ultralightManager.hasView(m_viewId)) {
        g_ultralightManager.setViewFocus(m_viewId, true);
        return true;
    }
#endif
    return UIWidget::onMousePress(mousePos, button);
}

bool UIUltralight::onMouseRelease(const Point& mousePos, Fw::MouseButton button)
{
#if OTCLIENT_HAS_ULTRALIGHT
    if (g_ultralightManager.isInitialized() && g_ultralightManager.hasView(m_viewId)) {
        return true;
    }
#endif
    return UIWidget::onMouseRelease(mousePos, button);
}

bool UIUltralight::onMouseMove(const Point& mousePos, const Point& mouseMoved)
{
#if OTCLIENT_HAS_ULTRALIGHT
    if (g_ultralightManager.isInitialized() && g_ultralightManager.hasView(m_viewId)) {
        return true;
    }
#endif
    return UIWidget::onMouseMove(mousePos, mouseMoved);
}

bool UIUltralight::onMouseWheel(const Point& mousePos, Fw::MouseWheelDirection direction)
{
#if OTCLIENT_HAS_ULTRALIGHT
    if (g_ultralightManager.isInitialized() && g_ultralightManager.hasView(m_viewId)) {
        return true;
    }
#endif
    return UIWidget::onMouseWheel(mousePos, direction);
}

bool UIUltralight::onKeyPress(uint8_t keyCode, int keyboardModifiers, int autoRepeatTicks)
{
#if OTCLIENT_HAS_ULTRALIGHT
    if (g_ultralightManager.isInitialized() && g_ultralightManager.hasView(m_viewId)) {
        return true;
    }
#endif
    return UIWidget::onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks);
}
