#include "variantlistmodel.h"

#include "proxmoxconsts.h"

#include <QSet>

VariantListModel::VariantListModel(QStringList keyFields, QObject *parent)
    : QAbstractListModel(parent)
    , m_keyFields(std::move(keyFields)) {}

int VariantListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant VariantListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }
    if (role == ItemDataRole) {
        return m_rows.at(index.row());
    }
    return {};
}

QHash<int, QByteArray> VariantListModel::roleNames() const {
    return {{ItemDataRole, QByteArrayLiteral("itemData")}};
}

QVariantMap VariantListModel::get(int row) const {
    if (row < 0 || row >= m_rows.size()) {
        return {};
    }
    return m_rows.at(row);
}

QString VariantListModel::keyOf(const QVariantMap &row) const {
    QString key;
    for (const QString &field : m_keyFields) {
        key += row.value(field).toString();
        key += QLatin1Char('|');
    }
    return key;
}

void VariantListModel::applyItems(const QVariantList &items) {
    const int oldCount = int(m_rows.size());

    // Target order, first occurrence wins on duplicate keys.
    QVector<QVariantMap> target;
    QVector<QString> targetKeys;
    QSet<QString> seen;
    target.reserve(items.size());
    targetKeys.reserve(items.size());
    for (const QVariant &value : items) {
        const QVariantMap row = value.toMap();
        const QString key = keyOf(row);
        if (seen.contains(key)) {
            continue;
        }
        seen.insert(key);
        target.push_back(row);
        targetKeys.push_back(key);
    }

    // Pass 1: drop rows whose key disappeared.
    for (int i = int(m_rows.size()) - 1; i >= 0; --i) {
        if (!seen.contains(m_keys.at(i))) {
            beginRemoveRows(QModelIndex(), i, i);
            m_rows.removeAt(i);
            m_keys.removeAt(i);
            endRemoveRows();
        }
    }

    // Pass 2: walk target positions; insert, move, or update in place.
    for (int t = 0; t < target.size(); ++t) {
        const QString &wantKey = targetKeys.at(t);

        if (t < m_rows.size() && m_keys.at(t) == wantKey) {
            if (m_rows.at(t) != target.at(t)) {
                m_rows[t] = target.at(t);
                const QModelIndex idx = index(t);
                emit dataChanged(idx, idx, {ItemDataRole});
            }
            continue;
        }

        // Survivor sitting further down? Move it up to position t.
        int from = -1;
        for (int j = t + 1; j < m_rows.size(); ++j) {
            if (m_keys.at(j) == wantKey) {
                from = j;
                break;
            }
        }

        if (from >= 0) {
            beginMoveRows(QModelIndex(), from, from, QModelIndex(), t);
            m_rows.move(from, t);
            m_keys.move(from, t);
            endMoveRows();
            if (m_rows.at(t) != target.at(t)) {
                m_rows[t] = target.at(t);
                const QModelIndex idx = index(t);
                emit dataChanged(idx, idx, {ItemDataRole});
            }
        } else {
            beginInsertRows(QModelIndex(), t, t);
            m_rows.insert(t, target.at(t));
            m_keys.insert(t, wantKey);
            endInsertRows();
        }
    }

    if (int(m_rows.size()) != oldCount) {
        emit countChanged();
    }
    updateRunningCount();
}

void VariantListModel::clear() {
    if (m_rows.isEmpty()) {
        return;
    }
    beginResetModel();
    m_rows.clear();
    m_keys.clear();
    endResetModel();
    emit countChanged();
    updateRunningCount();
}

void VariantListModel::updateRunningCount() {
    int running = 0;
    for (const QVariantMap &row : m_rows) {
        const QString status = row.value(QStringLiteral("status")).toString();
        if (status == ProxmoxConst::Status::Running
            || status == QStringLiteral("online")) {
            running += 1;
        }
    }
    if (running != m_runningCount) {
        m_runningCount = running;
        emit runningCountChanged();
    }
}
