#pragma once
#include <QObject>
#include <QString>

/*
 * System-agnostic notifications via org.freedesktop.Notifications (D-Bus).
 * Works on KDE, GNOME, etc. Falls back to notify-send in QML if this fails.
 */
class Notifier : public QObject {
    Q_OBJECT

public:
    explicit Notifier(QObject *parent = nullptr);

    // Returns true if the D-Bus Notify call was sent successfully.
    Q_INVOKABLE bool notify(const QString &title,
                            const QString &message,
                            const QString &iconName = QStringLiteral("proxmox-monitor"),
                            int timeoutMs = 5000);
};
