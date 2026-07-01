# 📹 Flutter Video Platform Client

Клиентское приложение для видеоплатформы с поддержкой:

- загрузки видео;
- воспроизведения HLS;
- Live Streaming (RTMP → HLS);
- управления видео.

---

## Скриншоты

<p align="center">
  <img src="lib/images/app_overview.png" width="1000" alt="Скриншоты приложения">
</p>

---

## 🚀 Возможности

### 🎬 Видео

- Список видео с поиском
- Просмотр деталей видео
- HLS-воспроизведение
- Поддержка выбора качества (Adaptive Streaming)
- Отображение:
  - длительности;
  - даты загрузки;
  - автора.

### ⬆️ Загрузка видео

- Выбор файла через `file_picker`
- Создание видео (metadata)
- Загрузка файла через Upload API
- Автоматический polling статуса:
  - uploading;
  - processing;
  - ready.
- Автоматический переход на экран просмотра после завершения обработки.

### 🔴 Live Streaming

- Захват камеры (через `rtmp_streaming`)
- RTMP-стрим на backend
- Автоматическое создание live-сессии
- Проверка доступности HLS (latency tracking)
- Статистика стрима:
  - bitrate;
  - fps;
  - отправленные байты.

### 📺 HLS Player

Кастомный плеер на базе `video_player`:

- автоматический retry при недоступном потоке;
- обработка состояния **stream not ready**;
- переключение качества;
- seek (если разрешён);
- управление громкостью;
- immersive mode (fullscreen без UI);
- fallback для Linux/Web.

### 🧪 Debug

- встроенный буфер сетевых логов;
- просмотр логов из интерфейса;
- копирование логов;
- очистка логов.

---

## 🏗 Архитектура

```text
lib/
├── screens/
│   ├── video_list_screen.dart
│   ├── video_detail_screen.dart
│   ├── upload_screen.dart
│   ├── live_screen.dart
│   └── live_lookup_screen.dart
│
├── repositories/
│   ├── video_repository.dart
│   ├── upload_repository.dart
│   ├── live_repository.dart
│   └── auth_repository.dart
│
├── core/
│   └── network/
│
├── widgets/
│   └── hls_player.dart
│
└── config/
    └── app_config.dart
```

---

## ⚙️ Используемые библиотеки

Основные зависимости:

- `dio` — HTTP-клиент;
- `video_player` — воспроизведение видео;
- `rtmp_streaming` — Live Streaming (кастомный пакет);
- `file_picker` — выбор файлов;
- `permission_handler` — доступ к камере и микрофону;
- `wakelock_plus` — предотвращение перехода устройства в режим сна во время стрима.

---

## ▶️ Запуск проекта

```bash
flutter pub get
flutter run
```

---

## ⚙️ Конфигурация

Адреса backend-сервисов передаются через `dart-define`:

```text
IDENTITY_BASE_URL
VIDEO_BASE_URL
UPLOAD_BASE_URL
LIVE_BASE_URL
ORIGIN_BASE_URL
ENABLE_NETWORK_LOGS
```

Пример запуска:

```bash
flutter run \
  --dart-define=IDENTITY_BASE_URL=http://192.168.1.12:8001 \
  --dart-define=VIDEO_BASE_URL=http://192.168.1.12:8003/api/v1 \
  --dart-define=UPLOAD_BASE_URL=http://192.168.1.12:8002/api/v1 \
  --dart-define=LIVE_BASE_URL=http://192.168.1.12:8004 \
  --dart-define=ORIGIN_BASE_URL=http://192.168.1.12:8080
```

---

## 📱 Поддерживаемые платформы

| Платформа | Поддержка |
| ---------- | --------- |
| Android | ✅ Полная |
| iOS | ✅ Полная |
| Linux | ⚠️ Fallback для HLS |
| Web | ⚠️ Ограниченная |

---

## 🔥 Как работает Live Streaming

1. Создаётся live-сессия через API.
2. Клиент получает `rtmp_url`.
3. Камера начинает RTMP-стрим.
4. Backend конвертирует поток в HLS.
5. Клиент:
   - проверяет доступность HLS;
   - измеряет latency.
6. После готовности поток переходит в состояние **LIVE**.

---

## 📡 Поток загрузки видео

```text
createVideo
    ↓
initUpload
    ↓
uploadFile
    ↓
completeUpload
    ↓
polling
    ↓
ready
```

---

## ⚠️ Особенности

- Используется polling вместо WebSocket.
- HLS может быть недоступен сразу после запуска — реализован механизм retry.
- Linux и Web не поддерживают нативное HLS-воспроизведение, используется fallback.
- Задержка Live Streaming определяется клиентом через проверку доступности HLS.

---

## 📌 TODO

- [ ] Перейти с polling на WebSocket.
- [ ] Вынести state management (Riverpod / Bloc).
- [ ] Добавить кэширование списка видео.
- [ ] Улучшить обработку ошибок.
- [ ] Добавить offline-режим.
- [ ] Добавить превью Live Stream.

---

## 👨‍💻 Автор

Проект разработан как Flutter-клиент для собственной видеоплатформы с backend на FastAPI.