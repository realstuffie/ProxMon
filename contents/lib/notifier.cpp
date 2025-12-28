#include "notifier.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingReply>
#include <QVariantList>

Notifier::Notifier(QObject *parent)
    : QObject(parent) {}

bool Notifier::notify(const QString &title,
                      const QString &message,
                      const QString &iconName,
                      int timeoutMs) {
    const QString service = QStringLiteral("org.freedesktop.Notifications");
    const QString path = QStringLiteral("/org/freedesktop/Notifications");
    const QString iface = QStringLiteral("org.freedesktop.Notifications");

    if (!QDBusConnection::sessionBus().isConnected()) {
        return false;
    }

    QDBusInterface i(service, path, iface, QDBusConnection::sessionBus());
    if (!i.isValid()) {
        return false;
    }

    // Notify(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout)
    QVariantList args;
    args << QStringLiteral("Proxmox Monitor");  // app_name
    args << uint(0);                            // replaces_id
    args << iconName;                           // app_icon
    args << title;                              // summary
    args << message;                            // body
    args << QStringList();                      // actions
    args << QVariantMap();                      // hints
    args << int(timeoutMs);                     // expire_timeout (ms)

    QDBusMessage m = QDBusMessage::createMethodCall(service, path, iface, QStringLiteral("Notify"));
    m.setArguments(args);

    // Best-effort; should be fast for notifications.
    QDBusPendingReply<uint> reply = QDBusConnection::sessionBus().asyncCall(m);
    reply.waitForFinished();
    return !reply.isError();
}
