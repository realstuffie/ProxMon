#include "vncframeview.h"
#include "vncclient.h"

#include <QPainter>
#include <QSGImageNode>
#include <QSGNode>
#include <QQuickWindow>

VncFrameView::VncFrameView(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(QQuickItem::ItemHasContents, true);
    setAcceptedMouseButtons(Qt::AllButtons);
    setFlag(QQuickItem::ItemAcceptsInputMethod);
    setFocus(true);
    setActiveFocusOnTab(true);
    setFlag(QQuickItem::ItemIsFocusScope);
}

void VncFrameView::setClient(VncClient *client)
{
    if (m_client == client) return;
    if (m_client) {
        QObject::disconnect(m_client, nullptr, this, nullptr);
    }
    m_client = client;
    if (m_client) {
        connect(m_client, &VncClient::frameUpdated,
                this, &VncFrameView::updateFrame);
        connect(m_client, &VncClient::frameSizeChanged, this, [this, client]() {
            prepareFrame(client->frameWidth(), client->frameHeight());
        });
        // A size may already be known (property set after connect started).
        prepareFrame(m_client->frameWidth(), m_client->frameHeight());
    }
    emit clientChanged();
}

// Returns the largest sub-rect of (0,0,viewW,viewH) that fits imgW×imgH
// with the aspect ratio preserved (letterbox / pillarbox).
static QRectF fitRect(qreal viewW, qreal viewH, qreal imgW, qreal imgH)
{
    if (viewW <= 0 || viewH <= 0 || imgW <= 0 || imgH <= 0)
        return QRectF();
    const qreal scale = qMin(viewW / imgW, viewH / imgH);
    return QRectF((viewW - imgW * scale) / 2.0,
                  (viewH - imgH * scale) / 2.0,
                  imgW * scale,
                  imgH * scale);
}

QRect VncFrameView::tileRect(int index) const
{
    const int col = index % m_tileCols;
    const int row = index / m_tileCols;
    return QRect(col * TileSize, row * TileSize, TileSize, TileSize)
        .intersected(m_frame.rect());
}

// Called on the render thread during the sync phase (main thread blocked).
//
// The node tree is one transform node with one image node per tile. Tile
// rects are in framebuffer pixels and the transform maps them into the
// letterboxed view rect. Resizing the item only changes the matrix, and
// neighbouring tiles share exact edges, so no seams appear between them.
QSGNode *VncFrameView::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (m_frame.isNull()) {
        delete oldNode;
        m_rebuildTiles = true;
        return nullptr;
    }

    auto *root = static_cast<QSGTransformNode *>(oldNode);
    if (!root) {
        root = new QSGTransformNode;
        m_rebuildTiles = true;  // new scene graph, so no tile has a texture yet
    }

    if (m_rebuildTiles) {
        while (QSGNode *child = root->firstChild()) {
            root->removeChildNode(child);
            delete child;
        }
        // createImageNode() returns the backend-native node for OpenGL,
        // Vulkan or Metal. With setOwnsTexture(true), setTexture() frees the
        // previous texture, so never delete one by hand. Each tile gets its
        // texture before it joins the tree, because the software renderer
        // crashes on a tile without one.
        for (int i = 0; i < m_tileDirty.size(); ++i) {
            QSGImageNode *tile = window()->createImageNode();
            tile->setFiltering(QSGTexture::Linear);
            tile->setOwnsTexture(true);
            tile->setRect(tileRect(i));
            tile->setTexture(window()->createTextureFromImage(m_frame.copy(tileRect(i))));
            root->appendChildNode(tile);
        }
        m_tileDirty.fill(false);  // every tile was just uploaded
        m_rebuildTiles = false;
    }

    // Upload only the tiles an update touched. Each texture gets its own
    // copy of the tile, so no texture holds a reference to m_frame. The next
    // paint into m_frame then skips the full-frame copy a shared image forces.
    int index = 0;
    for (QSGNode *child = root->firstChild(); child;
         child = child->nextSibling(), ++index) {
        if (!m_tileDirty.testBit(index)) continue;
        auto *tile = static_cast<QSGImageNode *>(child);
        tile->setTexture(window()->createTextureFromImage(m_frame.copy(tileRect(index))));
    }
    m_tileDirty.fill(false);

    const QRectF fit = fitRect(width(), height(), m_frame.width(), m_frame.height());
    QMatrix4x4 matrix;
    if (!fit.isEmpty()) {
        matrix.translate(fit.x(), fit.y());
        matrix.scale(fit.width() / m_frame.width(), fit.height() / m_frame.height());
    } else {
        matrix.scale(0);  // the item has no area, so draw nothing
    }
    root->setMatrix(matrix);
    return root;
}

void VncFrameView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (!m_frame.isNull())
        update();
}

void VncFrameView::releaseResources()
{
    QQuickItem::releaseResources();
}

void VncFrameView::prepareFrame(int w, int h)
{
    if (w <= 0 || h <= 0) return;
    if (m_frame.size() == QSize(w, h)) return;  // reconnect at same size keeps canvas
    m_frame = QImage(w, h, QImage::Format_ARGB32_Premultiplied);
    m_frame.fill(Qt::black);
    m_tileCols = (w + TileSize - 1) / TileSize;
    const int tileRows = (h + TileSize - 1) / TileSize;
    m_tileDirty = QBitArray(m_tileCols * tileRows, true);
    m_rebuildTiles = true;
    update();
}

void VncFrameView::updateFrame(const QImage &image, int x, int y, int w, int h)
{
    // No canvas yet: drop the rect. prepareFrame always precedes frames of a
    // given size (server init/resize emits frameSizeChanged first), so this
    // only skips data a later full update repaints anyway.
    if (m_frame.isNull() || image.isNull()) return;

    const QRect changed = QRect(x, y, w, h).intersected(m_frame.rect());
    if (changed.isEmpty()) return;

    QPainter painter(&m_frame);
    painter.setCompositionMode(QPainter::CompositionMode_Source);
    painter.drawImage(x, y, image);
    painter.end();

    // Mark every tile the changed rect overlaps.
    const int firstCol = changed.left() / TileSize;
    const int lastCol  = changed.right() / TileSize;
    const int firstRow = changed.top() / TileSize;
    const int lastRow  = changed.bottom() / TileSize;
    for (int row = firstRow; row <= lastRow; ++row) {
        for (int col = firstCol; col <= lastCol; ++col)
            m_tileDirty.setBit(row * m_tileCols + col);
    }
    update();
}
