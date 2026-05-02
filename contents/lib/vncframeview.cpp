#include "vncframeview.h"

#include <QPainter>
#include <QMutexLocker>

VncFrameView::VncFrameView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setAcceptedMouseButtons(Qt::AllButtons);
    setFlag(QQuickItem::ItemAcceptsInputMethod);
    setFocus(true);
    setActiveFocusOnTab(true);
    setFlag(QQuickItem::ItemIsFocusScope);
}

void VncFrameView::paint(QPainter *painter)
{
    QMutexLocker lock(&m_mutex);
    if (m_frame.isNull()) return;
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(QRectF(0, 0, width(), height()), m_frame);
}

void VncFrameView::updateFrame(const QImage &image)
{
    {
        QMutexLocker lock(&m_mutex);
        m_frame = image;
    }
    update();
}
