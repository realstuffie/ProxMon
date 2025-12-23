#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QVariant>

class ProxmoxClient : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString tokenId READ tokenId WRITE setTokenId NOTIFY tokenIdChanged)
    Q_PROPERTY(QString tokenSecret READ tokenSecret WRITE setTokenSecret NOTIFY tokenSecretChanged)
    Q_PROPERTY(bool ignoreSslErrors READ ignoreSslErrors WRITE setIgnoreSslErrors NOTIFY ignoreSslErrorsChanged)

public:
    explicit ProxmoxClient(QObject *parent = nullptr);

    QString host() const { return m_host; }
    void setHost(const QString &v);

    int port() const { return m_port; }
    void setPort(int v);

    QString tokenId() const { return m_tokenId; }
    void setTokenId(const QString &v);

    QString tokenSecret() const { return m_tokenSecret; }
    void setTokenSecret(const QString &v);

    bool ignoreSslErrors() const { return m_ignoreSslErrors; }
    void setIgnoreSslErrors(bool v);

    Q_INVOKABLE void requestNodes(int seq);
    Q_INVOKABLE void requestQemu(const QString &node, int seq);
    Q_INVOKABLE void requestLxc(const QString &node, int seq);

signals:
    void hostChanged();
    void portChanged();
    void tokenIdChanged();
    void tokenSecretChanged();
    void ignoreSslErrorsChanged();

    // kind: "nodes" | "qemu" | "lxc"
    void reply(int seq, const QString &kind, const QString &node, const QVariant &data);
    void error(int seq, const QString &kind, const QString &node, const QString &message);

private:
    void request(const QString &path, int seq, const QString &kind, const QString &node);

    QNetworkAccessManager m_nam;
    QString m_host;
    int m_port = 8006;
    QString m_tokenId;
    QString m_tokenSecret;
    bool m_ignoreSslErrors = false;
};
