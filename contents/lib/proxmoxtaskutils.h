#pragma once

#include <QString>
#include <QVariant>

namespace ProxmoxTaskUtils {

QString extractUpid(const QVariant &response);
bool isRunning(const QVariant &response);
QString exitMessage(const QVariant &response);

} // namespace ProxmoxTaskUtils
