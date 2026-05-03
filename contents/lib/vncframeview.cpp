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

void VncFrameView::updateFrame(const QImage &image, int x, int y, int w, int h)
{
    {
        QMutexLocker lock(&m_mutex);
        m_frame = image;
    }
    if (width() <= 0 || height() <= 0 || image.width() <= 0 || image.height() <= 0) {
        update();
        return;
    }
    qreal sx = qreal(width()) / image.width();
    qreal sy = qreal(height()) / image.height();
    update(QRect(int(x * sx), int(y * sy),
                 int(w * sx) + 2, int(h * sy) + 2));
}
