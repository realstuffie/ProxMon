#pragma once

#include <QQuickPaintedItem>
#include <QImage>
#include <QMutex>

class VncFrameView : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit VncFrameView(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

public slots:
    void updateFrame(const QImage &image, int x, int y, int w, int h);

private:
    QImage m_frame;
    QMutex m_mutex;
};
