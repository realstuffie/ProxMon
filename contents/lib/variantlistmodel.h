#pragma once

#include <QAbstractListModel>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

/*  Diffing list model over QVariantMap rows.

    Rows are the same QVariantMaps the controller already builds from API
    responses. applyItems() diffs the incoming (pre-sorted) list against the
    current rows by key:

      - rows whose key disappeared        -> removeRows
      - rows whose key is new             -> insertRows
      - surviving rows in a new position  -> moveRows
      - surviving rows whose map changed  -> dataChanged (single role)

    A refresh where nothing changed emits nothing, so QML delegates bound to
    this model persist across refreshes instead of being rebuilt. Duplicate
    keys in the input are dropped (first occurrence wins) which doubles as
    the multi-host dedupe.

    The key is the concatenation of the values of keyFields (set once at
    construction time by the owner; not a QML API).
*/
class VariantListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int runningCount READ runningCount NOTIFY runningCountChanged)

public:
    enum Roles {
        ItemDataRole = Qt::UserRole + 1,
    };

    explicit VariantListModel(QStringList keyFields, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_rows.size()); }
    int runningCount() const { return m_runningCount; }

    Q_INVOKABLE QVariantMap get(int row) const;

    // Replace contents with `items` (already sorted by the owner), emitting
    // granular change signals. Not a reset unless the model was empty.
    void applyItems(const QVariantList &items);

    void clear();

signals:
    void countChanged();
    void runningCountChanged();

private:
    QString keyOf(const QVariantMap &row) const;
    void updateRunningCount();

    QStringList m_keyFields;
    QVector<QVariantMap> m_rows;
    QVector<QString> m_keys;  // parallel to m_rows
    int m_runningCount = 0;
};
