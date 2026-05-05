# 📹 Flutter Video Platform Client

Клиентское приложение для видеоплатформы с поддержкой:

* загрузки видео
* воспроизведения HLS
* live стриминга (RTMP → HLS)
* управления видео

---

## 🚀 Возможности

### 🎬 Видео

* Список видео с поиском
* Просмотр деталей видео
* HLS-воспроизведение
* Поддержка выбора качества (adaptive streaming)
* Отображение:

  * длительности
  * даты загрузки
  * автора

---

### ⬆️ Загрузка видео

* Выбор файла через `file_picker`
* Создание видео (metadata)
* Загрузка файла (upload API)
* Автоматический polling статуса:

  * uploading
  * processing
  * ready
* Автопереход на экран просмотра после готовности

---

### 🔴 Live streaming

* Захват камеры (rtmp_streaming)
* RTMP стрим на backend
* Автоматическое создание live-сессии
* Проверка доступности HLS
* Статистика стрима:

  * bitrate
  * fps
  * отправленные байты

---

### 📺 HLS Player

* авто-retry при недоступном потоке
* обработка stream not ready
* переключение качества
* seek (если разрешено)
* volume control
* immersive mode
* fallback для Linux/Web

---

## 🏗 Архитектура

```
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
├── widgets/
│   └── hls_player.dart
│
└── config/
    └── app_config.dart
```

---

## ▶️ Запуск

```
flutter pub get
flutter run
```

---

## 📱 Платформы

* Android — ✅
* iOS — ✅
* Linux — ⚠️ без HLS
* Web — ⚠️ ограничено

---

## 📡 Upload pipeline

```
createVideo → initUpload → uploadFile → completeUpload → ready
```

---

## ⚠️ Особенности

* polling вместо WebSocket
* HLS появляется с задержкой
* Linux/Web fallback

---

## 📌 TODO

* WebSocket
* State management
* Кэширование
* Offline режим
