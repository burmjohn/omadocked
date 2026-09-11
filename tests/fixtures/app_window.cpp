// Explicitly owned Wayland integration fixture; never enumerates other windows.
// Build only through tests/unit/running_app_contract.py --native-apps.
#include <QApplication>
#include <QFile>
#include <QLabel>
#include <QSocketNotifier>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <cerrno>
#include <cstring>
#include <memory>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static std::unique_ptr<QWidget> window(const QString &label) {
    auto result = std::make_unique<QWidget>();
    result->setWindowTitle(label);
    result->resize(360, 140);
    auto *layout = new QVBoxLayout(result.get());
    layout->addWidget(new QLabel(label, result.get()));
    layout->addWidget(new QLabel("Temporary integration fixture; closes automatically.", result.get()));
    result->show();
    return result;
}

int main(int argc, char **argv) {
    if (argc != 4 || !QString::fromLocal8Bit(argv[1]).startsWith("omadocked-test-app-"))
        return 2;
    QApplication app(argc, argv);
    const QString appId = QString::fromLocal8Bit(argv[1]);
    QGuiApplication::setDesktopFileName(appId);
    const auto path = (QString::fromLocal8Bit(argv[2]) + "/" + QString::number(getpid()) + ".sock").toLocal8Bit();
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (static_cast<size_t>(path.size()) >= sizeof(address.sun_path))
        return 3;
    std::memcpy(address.sun_path, path.constData(), static_cast<size_t>(path.size()) + 1);
    const int server = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (server < 0 || bind(server, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0 || listen(server, 4) != 0)
        return 4;
    QFile receipt(QString::fromLocal8Bit(argv[3]));
    if (!receipt.open(QIODevice::WriteOnly | QIODevice::Append) ||
        receipt.write(QByteArray::number(getpid()) + '\n') <= 0 || !receipt.flush())
        return 5;
    receipt.close();
    auto first = window("Omadocked owned native fixture");
    std::unique_ptr<QWidget> second;
    QSocketNotifier notifier(server, QSocketNotifier::Read, &app);
    QObject::connect(&notifier, &QSocketNotifier::activated, &app, [&] {
        const int client = accept4(server, nullptr, nullptr, SOCK_CLOEXEC);
        if (client < 0)
            return;
        const timeval timeout{1, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        char buffer[32]{};
        const auto size = recv(client, buffer, sizeof(buffer), 0);
        const QByteArray operation(buffer, size > 0 ? static_cast<qsizetype>(size) : 0);
        bool valid = true;
        if (operation == "second" && !second) {
            second = window("Omadocked owned second native fixture");
        } else if (operation == "close-second" && second) {
            second.reset();
        } else if (operation == "quit") {
            QTimer::singleShot(0, &app, &QApplication::quit);
        } else {
            valid = false;
        }
        const char *reply = valid ? "ok" : "error";
        send(client, reply, std::strlen(reply), MSG_NOSIGNAL);
        close(client);
    });
    // Independent fail-safe if the parent harness crashes or is interrupted.
    QTimer::singleShot(120000, &app, &QApplication::quit);
    const int result = app.exec();
    notifier.setEnabled(false);
    close(server);
    unlink(path.constData());
    return result;
}
