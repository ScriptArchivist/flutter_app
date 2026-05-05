# 📹 Flutter Video Platform Client

Клиентское приложение для видеоплатформы с поддержкой:
- загрузки видео
- воспроизведения HLS
- live стриминга (RTMP → HLS)
- управления видео

---

## 🚀 Возможности

### 🎬 Видео
- Список видео с поиском
- Просмотр деталей видео
- HLS-воспроизведение
- Поддержка выбора качества (adaptive streaming)
- Отображение:
  - длительности
  - даты загрузки
  - автора

---

### ⬆️ Загрузка видео
- Выбор файла через `file_picker`
- Создание видео (metadata)
- Загрузка файла (upload API)
- Автоматический polling статуса:
  - `uploading`
  - `processing`
  - `ready`
- Автопереход на экран просмотра после готовности

---

### 🔴 Live streaming
- Захват камеры (через `rtmp_streaming`)
- RTMP стрим на backend
- Автоматическое создание live-сессии
- Проверка доступности HLS (latency tracking)
- Статистика стрима:
  - bitrate
  - fps
  - отправленные байты

---

### 📺 HLS Player
Кастомный плеер на базе `video_player`:
- авто-retry при недоступном потоке
- обработка "stream not ready"
- переключение качества
- seek (если разрешено)
- volume control
- immersive mode (fullscreen без UI)
- fallback для Linux/Web

---

### 🧪 Debug
- встроенный буфер сетевых логов
- просмотр / копирование / очистка логов из UI

---

## 🏗 Архитектура


lib/
├── screens/
│ ├── video_list_screen.dart
│ ├── video_detail_screen.dart
│ ├── upload_screen.dart
│ ├── live_screen.dart
│ └── live_lookup_screen.dart
│
├── repositories/
│ ├── video_repository.dart
│ ├── upload_repository.dart
│ ├── live_repository.dart
│ └── auth_repository.dart
│
├── core/
│ └── network/
│
├── widgets/
│ └── hls_player.dart
│
└── config/
└── app_config.dart


---

## ⚙️ Зависимости

Основные:

- `dio` — HTTP клиент
- `video_player` — воспроизведение видео
- `rtmp_streaming` — live стриминг (кастомный пакет)
- `file_picker` — выбор файлов
- `permission_handler` — доступ к камере/микрофону
- `wakelock_plus` — предотвращение sleep во время стрима

---

## ▶️ Запуск проекта

```bash
flutter pub get
flutter run
📱 Платформы
Платформа	Поддержка
Android	✅ Полная
iOS	✅ Полная
Linux	⚠️ без HLS (fallback)
Web	⚠️ ограничено
🔥 Live поток — как работает
Создаётся live-сессия через API
Получается rtmp_url
Камера начинает стримить в RTMP
Backend конвертирует в HLS
Клиент:
проверяет доступность HLS
измеряет latency
После готовности → состояние LIVE
📡 Поток загрузки видео
createVideo → initUpload → uploadFile → completeUpload → polling → ready
⚠️ Особенности
Используется polling вместо WebSocket
HLS может быть недоступен сразу → реализованы retry
Linux/Web не поддерживают нативный HLS player
Live latency определяется клиентом через HLS availability check
📌 TODO / Возможные улучшения
 Перейти с polling на WebSocket
 Вынести state management (Riverpod / Bloc)
 Кэширование списка видео
 Улучшить обработку ошибок
 Добавить offline режим
 Добавить превью live stream
👨‍💻 Автор

Проект разработан как клиент для видеоплатформы (FastAPI backend).