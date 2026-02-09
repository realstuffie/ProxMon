#pragma once
#include <QObject>
#include <QString>

/*
 * System-agnostic notifications via org.freedesktop.Notifications (D-Bus).
 *
 * SECURITY: We intentionally do not execute external commands (e.g. notify-send) from QML.
 * If D-Bus notifications fail, the UI should silently drop the notification.
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
