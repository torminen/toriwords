# ToriWords iOS — UI copy

This file lists every user-visible string in the iOS app, in English and Russian. Where each string appears is in [ui.md](ui.md), and the behaviour behind it is in [product.md](product.md).

## 1. Conventions

- **Source.** The strings come from the three String Catalogs: `ios/App/Localizable.xcstrings` (section 2), `ios/WidgetExtension/Localizable.xcstrings` (section 3) and `ios/ShareExtension/Localizable.xcstrings` (section 4). English is the source language; Russian is the only translation. The iOS strings are the reference: Android uses them word for word (see [android/docs/copy.md](../../android/docs/copy.md)).
- **Only strings in use are listed.** A catalog entry counts as in use when its text appears in the Swift code of its own target (`ios/App`, `ios/WidgetExtension` or `ios/ShareExtension`, plus the shared package `ios/ToriKit`) as a `Text`, `Button`, `String(localized:)`, `LocalizedStringResource` or similar literal, with interpolations standing for the placeholders. Entries that fail this test, and entries in use without Russian, are listed in section 7.
- **Grouping.** Section 2 is grouped by the screen where a string first appears; "also …" in the note names other screens that use the same string.
- **Placeholders** are written `{n}`, `{m}`, `{k}` for numbers and `{word}`, `{tag}`, `{text}` and so on for text. Russian uses the same names, so word order can change. The names match [android/docs/copy.md](../../android/docs/copy.md).
- **Plurals** are separated by `|`. English has two forms (one | other). Russian has three (one | few | many: 1 слово | 2 слова | 5 слов).
- **Quotes:** English uses “ ”, Russian uses « ».
- **Language.** The interface language follows the iOS per-app language (Settings → ToriWords → Language): English or Russian; any other language falls back to English. Words, sentences and translations are never translated by the interface language.
- **Product name:** "ToriWords" in both languages, never translated or declined.
- **Dates and times** (the widget date, "Synced 2 min ago", the reminder time, "Next review: in N days") are formatted by the system in the app language.
- **The same English string with two Russian texts** (for example Learning, Known) appears twice, with a note on where each is used.

## 2. App strings

### 2.1 Home and launch

Behaviour: [First run, Home and launch](product.md#510-first-run-home-and-launch).

| English | Russian | Where / note |
|---|---|---|
| Add a word… | Добавить слово… | also Add |
| Add your first word | Добавить первое слово |  |
| All done for today | На сегодня всё | also Review |
| All done for today, {next review} | На сегодня всё, {next review} |  |
| All words › | Все слова › |  |
| Build your vocabulary | Пополняйте словарный запас | also Progress |
| Due today › | На сегодня › |  |
| Due today, {summary} | На сегодня: {summary} |  |
| From any app — select text → Share → ToriWords | Из любого приложения — выделите текст → Поделиться → ToriWords |  |
| Next review: in {n} day \| Next review: in {n} days | Следующее повторение: через {n} день \| Следующее повторение: через {n} дня \| Следующее повторение: через {n} дней | plural |
| Next review: tomorrow | Следующее повторение: завтра |  |
| No translation found — add your own | Перевод не найден — добавьте свой | also Entry |
| No translation yet | Перевода пока нет |  |
| Nothing to review today | Сегодня нечего повторять | also Review |
| Opens words that need a translation. | Открывает слова, которым нужен перевод. |  |
| Opens your progress. | Открывает ваш прогресс. |  |
| Recently added | Недавно добавленные |  |
| Review | Повторить |  |
| Settings | Настройки | also Settings |
| Starts today's review. | Начинает сегодняшнее повторение. |  |
| ToriWords could not open its data | ToriWords не удалось открыть данные |  |
| Translation pending | Перевод ожидается | also Entry |
| Type it — tap “Add a word…” above | Введите его — нажмите «Добавить слово…» вверху |  |
| Welcome back — {n} card is waiting. We'll spread them over about a week. \| Welcome back — {n} cards are waiting. We'll spread them over about a week. | С возвращением! Вас ждёт {n} карточка. Мы распределим их примерно на неделю. \| С возвращением! Вас ждут {n} карточки. Мы распределим их примерно на неделю. \| С возвращением! Вас ждут {n} карточек. Мы распределим их примерно на неделю. | plural |
| Words | Слова | also Words |
| Words you add come back for review just before you forget them. | Добавленные слова возвращаются на повторение как раз перед тем, как вы их забудете. | also Progress |
| Works offline: the dictionary is built in. | Работает офлайн: словарь встроен. |  |
| {n} new | Новых: {n} |  |
| {n} to review | Повторить: {n} | also the reminder notification text; also Reminders and widget hint |
| {n} to review · {m} new | Повторить: {n} · Новых: {m} |  |
| {n} word needs a translation \| {n} words need a translation | {n} слову нужен перевод \| {n} словам нужен перевод \| {n} словам нужен перевод | plural |

### 2.2 Add

Behaviour: [Add a word by typing](product.md#51-add-a-word-by-typing).

| English | Russian | Where / note |
|---|---|---|
| Add | Добавить | also Words, Entry, Related words |
| Already in your vocabulary | Уже в вашем словаре |  |
| Continue | Продолжить |  |
| Definition | Определение | also Entry |
| In this sentence: {machine translation} | В этом предложении: {machine translation} |  |
| In your vocabulary | В вашем словаре |  |
| No suggestions: the word is not in the dictionary, and on-device translation isn't available. Type a translation (optional). | Вариантов нет: слова нет в словаре, а перевод на устройстве недоступен. Введите перевод (необязательно). |  |
| OK | ОК | also Review, Entry, Pronunciation, Settings, Settings: iCloud sync, Settings: Data and Export |
| Open word | Открыть слово |  |
| Related to “{word}” | Связано с «{word}» |  |
| Resume learning | Продолжить изучение | also Words, Entry |
| Save | Сохранить | also Tags |
| Save adds newly checked meanings and the sentence. | При сохранении добавятся отмеченные новые значения и предложение. |  |
| Save adds the sentence and meanings. | При сохранении добавятся предложение и значения. |  |
| Save as | Сохранить как |  |
| Saved | Сохранено |  |
| Sentence (optional) | Предложение (необязательно) |  |
| Something went wrong | Что-то пошло не так | also Review, Entry, Settings, Settings: iCloud sync, Settings: Data and Export |
| Source (optional) | Источник (необязательно) | also Entry |
| Tags | Теги | also Entry, Tags, Settings: Data and Export |
| Tap the word to save | Нажмите на слово, чтобы сохранить его |  |
| The text is kept as the sentence. | Текст сохранится как предложение. |  |
| Translation | Перевод | also Entry, Settings, Settings: Translation |
| Type a translation (optional) | Введите перевод (необязательно) |  |
| Type the English word or phrase | Введите английское слово или фразу |  |
| You marked this as known | Вы отметили это слово как известное |  |
| You paused this word | Вы поставили это слово на паузу |  |

### 2.3 Review

Behaviour: [Review](product.md#56-review).

| English | Russian | Where / note |
|---|---|---|
| Add a word | Добавить слово | also Words, Progress |
| Add words to start reviewing | Добавьте слова, чтобы начать повторение |  |
| blank | пропуск | VoiceOver, for the blank in a sentence |
| Cancel | Отменить | also Words, Entry, Tags, Settings: iCloud sync, Settings: Data and Export |
| Card {n} of {m} | Карточка {n} из {m} | VoiceOver |
| Close | Закрыть | also Related words |
| Delete | Удалить | also Words, Entry, Tags |
| Delete “{word}”? | Удалить «{word}»? | also Words, Entry |
| Done | Готово | also Words, Entry |
| Edit | Изменить | also Entry |
| Fill in the missing word | Вставьте пропущенное слово |  |
| I already know this | Я это уже знаю | also Words, Entry |
| It is removed with its review history on all your devices. | Слово и история его повторений будут удалены на всех ваших устройствах. | also Words, Entry |
| Learn more new words | Учить ещё новые слова |  |
| More | Ещё | also Words, Entry |
| Not now | Не сейчас | also Reminders and widget hint |
| Only on days when cards are due. No streaks. | Только в дни, когда есть карточки. Без серий. |  |
| Pause | Пауза | also Words, Entry |
| Play sentence | Произнести предложение | also Pronunciation |
| Practice done | Тренировка завершена |  |
| Practice · {n} / {m} | Тренировка · {n} / {m} |  |
| Remembered → | Помню → |  |
| Remind you to review every day? | Напоминать о повторении каждый день? |  |
| Reminder time | Время напоминания |  |
| Say it in English | Скажите по-английски |  |
| Tap to show answer | Нажмите, чтобы увидеть ответ |  |
| Turn on reminder | Включить напоминание |  |
| Undo last answer | Отменить последний ответ |  |
| {n} cards reviewed · {m} remembered · {k} new words | Повторено: {n} · Помню: {m} · Новых слов: {k} |  |
| {n} cards · {m} remembered | Карточек: {n} · Помню: {m} |  |
| ← Forgot | ← Забыл |  |

### 2.4 Words

Behaviour: [Words and the entry screen](product.md#57-words-and-the-entry-screen).

| English | Russian | Where / note |
|---|---|---|
| Add tags | Добавить теги |  |
| Add “{text}” | Добавить «{text}» |  |
| Adds tags to {n} word. Tags it already has stay. \| Adds tags to {n} words. Tags they already have stay. | Теги добавятся к {n} слову. Уже имеющиеся теги останутся. \| Теги добавятся к {n} словам. Уже имеющиеся теги останутся. \| Теги добавятся к {n} словам. Уже имеющиеся теги останутся. | plural |
| All | Все |  |
| A–Z | А–Я |  |
| Clear | Сбросить |  |
| Delete {n} word \| Delete {n} words | Удалить {n} слово \| Удалить {n} слова \| Удалить {n} слов | plural |
| Delete {n} word? \| Delete {n} words? | Удалить {n} слово? \| Удалить {n} слова? \| Удалить {n} слов? | plural |
| Deselect all | Снять выбор |  |
| Filter by tag | Фильтр по тегам |  |
| Known | Знаю | Words select-mode toolbar (VoiceOver reads “I already know this”) |
| Newest | Сначала новые |  |
| Next due | По дате повторения |  |
| No tags yet. Add tags to words in Add or when editing a word. | Тегов пока нет. Добавляйте теги при добавлении слова или при его редактировании. |  |
| No words match “{text}” | Нет слов по запросу «{text}» |  |
| Phrases | Фразы |  |
| Search words, translations, sentences | Поиск по словам, переводам, предложениям |  |
| Select | Выбрать |  |
| Select all | Выбрать все |  |
| Show {n} word \| Show {n} words | Показать {n} слово \| Показать {n} слова \| Показать {n} слов | plural |
| Sort | Сортировка |  |
| Tag | Тег |  |
| They are removed with their review history on all your devices. | Они будут удалены вместе с историей повторений на всех ваших устройствах. |  |
| Undo | Отменить | the Undo toast on every screen |
| {n} selected \| {n} selected | Выбрано: {n} \| Выбрано: {n} \| Выбрано: {n} | plural |
| {n} word deleted \| {n} words deleted | {n} слово удалено \| {n} слова удалены \| {n} слов удалено | plural |
| {n} word · A–Z \| {n} words · A–Z | {n} слово · А–Я \| {n} слова · А–Я \| {n} слов · А–Я | plural |
| {n} word · newest first \| {n} words · newest first | {n} слово · сначала новые \| {n} слова · сначала новые \| {n} слов · сначала новые | plural |
| {n} word · next due first \| {n} words · next due first | {n} слово · по дате повторения \| {n} слова · по дате повторения \| {n} слов · по дате повторения | plural |
| {tag} +{n} | {tag} +{n} |  |
| “{word}” deleted | «{word}» удалено |  |

### 2.5 Entry

Behaviour: [Words and the entry screen](product.md#57-words-and-the-entry-screen).

| English | Russian | Where / note |
|---|---|---|
| Add meaning | Добавить значение |  |
| Add meaning {translation} | Добавить значение {translation} |  |
| Add sentence | Добавить предложение |  |
| Delete word | Удалить слово |  |
| Discard | Не сохранять |  |
| Discard changes? | Отменить изменения? |  |
| English → Russian | Английский → русский |  |
| Fill in the blank | Вставить пропущенное слово |  |
| IPA | Транскрипция (IPA) |  |
| Keep editing | Продолжить редактирование |  |
| Learning | Изучение | entry section heading; also Settings |
| Meanings | Значения |  |
| Merge | Объединить | also Tags |
| Merge combines meanings, sentences, tags and review history into one word. | При объединении значения, предложения, теги и история повторений соединятся в одном слове. |  |
| Not reviewed until it has a translation. | Не повторяется, пока нет перевода. |  |
| Note | Заметка |  |
| Part of speech | Часть речи |  |
| Russian → English | Русский → английский |  |
| Sentence | Предложение |  |
| Sentences | Предложения |  |
| Suggested meanings | Предлагаемые значения |  |
| This word was deleted on another device | Это слово удалено на другом устройстве |  |
| Try again | Повторить |  |
| Word or phrase | Слово или фраза |  |
| “{word}” is already in your vocabulary | «{word}» уже есть в вашем словаре |  |

### 2.6 Tags

Behaviour: [Tags](product.md#511-tags).

| English | Russian | Where / note |
|---|---|---|
| Add tag | Добавить тег |  |
| Add tags to words in Add or when editing a word. | Добавляйте теги при добавлении слова или при его редактировании. |  |
| Create tag “{text}” | Создать тег «{text}» |  |
| Delete tag “{tag}”? | Удалить тег «{tag}»? |  |
| It is removed from {n} word. The word stays. \| It is removed from {n} words. The words stay. | Тег будет убран из {n} слова. Сами слова останутся. \| Тег будет убран из {n} слов. Сами слова останутся. \| Тег будет убран из {n} слов. Сами слова останутся. | plural |
| Merge “{tag}” into “{other tag}”? | Объединить «{tag}» с «{other tag}»? |  |
| Name | Название |  |
| No tags yet | Тегов пока нет |  |
| Remove tag {tag} | Убрать тег {tag} |  |
| Rename tag | Переименовать тег |  |
| Renames the tag. | Переименовывает тег. |  |
| {n} word \| {n} words | {n} слово \| {n} слова \| {n} слов | plural |
| “{tag}” already exists | «{tag}» уже существует |  |

### 2.7 Related words

Behaviour: [Related words](product.md#513-related-words).

| English | Russian | Where / note |
|---|---|---|
| Add to my words | Добавить в мои слова |  |
| Hide {word} | Скрыть {word} |  |
| Related words | Связанные слова |  |
| You have all related words | Все связанные слова уже у вас |  |
| ✓ In vocabulary | ✓ В словаре |  |

### 2.8 Pronunciation

Behaviour: [Pronunciation](product.md#512-pronunciation).

| English | Russian | Where / note |
|---|---|---|
| No English voice | Нет английского голоса |  |
| Play pronunciation | Произнести |  |
| To hear words, download an English voice in Settings → Accessibility → Spoken Content → Voices → English. | Чтобы слышать слова, загрузите английский голос: Настройки → Универсальный доступ → Устный контент → Голоса → Английский. |  |

### 2.9 Progress

Behaviour: [Progress](product.md#515-progress).

| English | Russian | Where / note |
|---|---|---|
| Activity | Активность |  |
| Already known | Уже знаю |  |
| Captured | Добавлено |  |
| Doesn't change your schedule. | Не меняет расписание повторений. |  |
| new words | новых слов |  |
| Practice today's words | Повторить сегодняшние слова |  |
| Progress | Прогресс |  |
| reviewed | повторено |  |
| Reviews | Повторения |  |
| Reviews per day, last 30 days | Повторений в день за последние 30 дней |  |
| still due | осталось |  |
| Today | Сегодня |  |
| Top sources | Главные источники |  |
| Vocabulary | Словарный запас |  |
| Words added | Добавлено слов |  |
| Words added per week, last 8 weeks | Добавлено слов в неделю за последние 8 недель |  |

### 2.10 Settings

Behaviour: [Settings and About](product.md#59-settings-and-about).

| English | Russian | Where / note |
|---|---|---|
| About | О приложении | also Settings: About |
| Accent | Акцент |  |
| App language | Язык приложения |  |
| Auto-play on reveal | Произносить при показе ответа |  |
| Built-in dictionary | Встроенный словарь |  |
| Change in iOS Settings › | Изменить в Настройках iOS › |  |
| Changes the interface only. Your words, sentences and translations stay as they are. | Меняет только интерфейс. Ваши слова, предложения и переводы остаются как есть. |  |
| Counts words, not cards: each new word brings its cards. Applies on all your devices. | Считаются слова, а не карточки: у каждого нового слова свои карточки. Действует на всех ваших устройствах. |  |
| Daily reminder | Ежедневное напоминание |  |
| Data | Данные | also Settings: Data and Export |
| iCloud sync | Синхронизация iCloud | also Settings: iCloud sync |
| Language | Язык |  |
| New words per day | Новых слов в день |  |
| Notifications are off for ToriWords | Уведомления для ToriWords выключены |  |
| Open iOS Settings › | Открыть Настройки iOS › |  |
| Pronunciation | Произношение |  |
| Ready | Готово | also Settings: Translation |
| Reminders | Напоминания |  |
| Time | Время |  |
| UK | UK |  |
| UK English | Британский английский |  |
| US | US |  |
| US English | Американский английский |  |
| Widget | Виджет | also Reminders and widget hint |
| Words are spoken with this iPhone's English voice. Applies to this device only. | Слова произносит английский голос этого iPhone. Действует только на этом устройстве. |  |
| {n} new word a day \| {n} new words a day | {n} новое слово в день \| {n} новых слова в день \| {n} новых слов в день | plural |

### 2.11 Settings: Translation

Behaviour: [Settings and About](product.md#59-settings-and-about).

| English | Russian | Where / note |
|---|---|---|
| Apple Translation is not available on this device. The built-in dictionary still suggests translations. | Перевод Apple недоступен на этом устройстве. Встроенный словарь по-прежнему предлагает переводы. |  |
| Bundled | Встроенный |  |
| Dictionary (Wiktionary) | Словарь (Викисловарь) |  |
| Download | Загрузить |  |
| English → Russian translation runs on this iPhone once its language data is downloaded. Tap Download, or add English and Russian in iOS Settings → Apps → Translate → Downloaded Languages. The dictionary works without it. | Перевод с английского на русский работает прямо на iPhone, когда загружены языковые данные. Нажмите «Загрузить» или добавьте английский и русский в Настройках iOS → Приложения → Перевод → Загруженные языки. Словарь работает и без этого. |  |
| Not available | Недоступно |  |
| On-device translation | Перевод на устройстве |  |
| Translations for new words come from the built-in dictionary first, then from Apple Translation on this iPhone. | Переводы новых слов берутся сначала из встроенного словаря, затем из Перевода Apple на этом iPhone. |  |
| Version {version} | Версия {version} |  |

### 2.12 Settings: iCloud sync

Behaviour: [iCloud sync](product.md#58-icloud-sync).

| English | Russian | Where / note |
|---|---|---|
| Back up this device again | Снова сохранить это устройство в iCloud |  |
| Check your device time | Проверьте время на устройстве |  |
| Connect to the internet and try again. Nothing was changed. | Подключитесь к интернету и попробуйте снова. Ничего не изменилось. |  |
| Delete iCloud data | Удалить данные iCloud |  |
| Delete iCloud data… | Удалить данные iCloud… |  |
| Deleted | Удалены |  |
| iCloud data was deleted | Данные iCloud удалены |  |
| iCloud data was not deleted. Try again later. | Данные iCloud не удалены. Попробуйте позже. |  |
| iCloud is off: words stay on this device | iCloud выключен: слова остаются на этом устройстве |  |
| iCloud storage is full | Хранилище iCloud заполнено |  |
| No internet connection | Нет подключения к интернету |  |
| Not synced yet | Ещё не синхронизировано |  |
| Off | Выкл. |  |
| On | Вкл. |  |
| Open iOS Settings | Открыть настройки iOS |  |
| Status | Статус |  |
| Storage full | Хранилище заполнено |  |
| Sync now | Синхронизировать |  |
| Synced {time ago} | Синхронизировано {time ago} |  |
| Syncing… | Синхронизация… |  |
| This deletes your words from iCloud. Your other devices keep their copies but stop syncing. | Слова будут удалены из iCloud. Другие ваши устройства сохранят свои копии, но перестанут синхронизироваться. |  |
| Try again later. | Попробуйте позже. |  |
| Waiting for network | Ожидание сети |  |
| Your words sync through your private iCloud between devices signed in to the same Apple Account. To stop syncing on this device, turn off iCloud for ToriWords in iOS Settings; your words stay on this device. | Слова синхронизируются через ваш личный iCloud между устройствами с одним Apple Account. Чтобы остановить синхронизацию на этом устройстве, выключите iCloud для ToriWords в настройках iOS — слова останутся на этом устройстве. |  |

### 2.13 Settings: Data and Export

Behaviour: [Export and backup](product.md#516-export-and-backup).

| English | Russian | Where / note |
|---|---|---|
| Add words to export them. | Добавьте слова, чтобы их экспортировать. |  |
| All your words, review history and tags are deleted from this device. This can't be undone. | Все ваши слова, история повторений и теги будут удалены с этого устройства. Это нельзя отменить. |  |
| Backup (JSON) | Резервная копия (JSON) |  |
| Backup restored | Резервная копия восстановлена |  |
| Choose a .json file exported from ToriWords. Nothing was changed. | Выберите файл .json, экспортированный из ToriWords. Ничего не изменилось. |  |
| Everything, including review history. Use it to restore. | Всё, включая историю повторений. Из неё можно восстановить данные. |  |
| Export | Экспорт |  |
| Export {n} word \| Export {n} words | Экспортировать {n} слово \| Экспортировать {n} слова \| Экспортировать {n} слов | plural |
| Files with dictionary data include the Wiktionary attribution (CC BY-SA). | Файлы с данными словаря содержат указание на Викисловарь (CC BY-SA). |  |
| Imported {n} words, {m} merged with existing. | Импортировано слов: {n}, из них объединено с существующими: {m}. |  |
| One row per word. No review history; can't be restored. | Одна строка на слово. Без истории повторений, восстановить из неё нельзя. |  |
| Preparing backup… | Подготовка резервной копии… |  |
| Preparing spreadsheet… | Подготовка таблицы… |  |
| Remove | Удалить |  |
| Remove all data from this device | Удалить все данные с этого устройства |  |
| Remove all data from this device? | Удалить все данные с этого устройства? |  |
| Restore from backup | Восстановить из копии |  |
| Restoring… | Восстановление… |  |
| Spreadsheet (CSV) | Таблица (CSV) |  |
| This backup was made by a newer version of ToriWords. Update the app to restore it. Nothing was changed. | Эта копия создана более новой версией ToriWords. Обновите приложение, чтобы её восстановить. Ничего не изменилось. |  |
| This is not a ToriWords backup | Это не резервная копия ToriWords |  |
| Update the app | Обновите приложение |  |
| Your words are deleted from this device. They stay in iCloud and come back at the next sync, unless you delete iCloud data in Settings → iCloud sync. | Слова будут удалены с этого устройства. Они останутся в iCloud и вернутся при следующей синхронизации, если не удалить данные iCloud в разделе Настройки → Синхронизация iCloud. |  |
| {n} unsynced change will be lost. \| {n} unsynced changes will be lost. | {n} несинхронизированное изменение будет потеряно. \| {n} несинхронизированных изменения будут потеряны. \| {n} несинхронизированных изменений будут потеряны. | plural |
| {n} word was deleted earlier and was not restored. \| {n} words were deleted earlier and were not restored. | {n} слово было удалено раньше и не восстановлено. \| {n} слова были удалены раньше и не восстановлены. \| {n} слов были удалены раньше и не восстановлены. | plural |
| {message} {extra line} | {message} {extra line} | joins a message and an extra line; no words of its own |

### 2.14 Settings: About

Behaviour: [Settings and About](product.md#59-settings-and-about).

| English | Russian | Where / note |
|---|---|---|
| Attribution | Источники данных |  |
| Dictionary data | Данные словаря |  |
| Dictionary data from Wiktionary, CC BY-SA | Данные словаря из Викисловаря, CC BY-SA |  |
| Libraries | Библиотеки |  |
| Licences | Лицензии |  |
| Privacy | Конфиденциальность |  |
| Source code | Исходный код |  |
| The ToriWords name, logo and app icon are not covered by this licence. | Название, логотип и значок ToriWords не подпадают под эту лицензию. |  |
| Version | Версия |  |
| Your words are stored on this device and, if iCloud is on, in your private iCloud. Nobody else, including us, can read them. No analytics, tracking or crash-reporting SDKs; no usage data is collected. Only the crash and performance reports of iOS itself exist, if you allowed them in iOS Settings. | Ваши слова хранятся на этом устройстве и, если iCloud включён, в вашем личном iCloud. Никто другой, включая нас, не может их прочитать. Никакой аналитики, отслеживания и SDK для отчётов о сбоях; данные об использовании не собираются. Есть только отчёты о сбоях и производительности самой iOS, если вы разрешили их в Настройках iOS. |  |

### 2.15 Reminders and widget hint

Behaviour: [Reminders and widget](product.md#514-reminders-and-widget).

| English | Russian | Where / note |
|---|---|---|
| Add the ToriWords widget | Добавьте виджет ToriWords |  |
| Today's cards on your Home Screen: touch and hold an empty area, tap Edit → Add Widget, then find ToriWords. | Карточки на сегодня — прямо на экране «Домой»: нажмите и удерживайте пустое место, затем «Править» → «Добавить виджет» и найдите ToriWords. |  |

### 2.16 Shared components

Strings defined in the shared UI package (`ios/ToriKit/Sources/ToriUI`) and used on several screens.

| English | Russian | Where / note |
|---|---|---|
| Check translation | Проверьте перевод |  |
| Forgot | Забыл |  |
| Known | Знаю | stage badge and filter chip |
| Known well | Хорошо знаю |  |
| Learning | Изучается | stage badge, filter chip, Progress row |
| Machine translation | Машинный перевод |  |
| Needs translation | Нужен перевод |  |
| New | Новое |  |
| Paused | На паузе |  |
| Remembered | Помню |  |
| Translation added automatically. Check it. | Перевод добавлен автоматически. Проверьте его. |  |
| Wiktionary | Викисловарь |  |

## 3. Widget strings

Behaviour: [Reminders and widget](product.md#514-reminders-and-widget). The widget's gallery name is the display name "ToriWords" (section 5).

| English | Russian | Where / note |
|---|---|---|
| Cards to review today. | Карточки на сегодня. |  |
| Next review: tomorrow | Следующее повторение: завтра |  |
| Next review: {date} | Следующее повторение: {date} |  |
| Open ToriWords | Откройте ToriWords |  |
| Tap to start reviewing | Нажмите, чтобы начать |  |
| to review | повторить |  |
| {n} new | Новых: {n} |  |
| {n} to review | Повторить: {n} |  |
| {n} to review · {m} new | Повторить: {n} · Новых: {m} |  |

## 4. Capture sheet strings

Behaviour: [Capture via Share](product.md#52-capture-via-share). The sheet's title is the product name, "ToriWords".

| English | Russian | Where / note |
|---|---|---|
| Already in your vocabulary | Уже в вашем словаре |  |
| Cancel | Отменить |  |
| Could not save. Open ToriWords once, then try again. | Не удалось сохранить. Откройте ToriWords и попробуйте снова. |  |
| In the share menu, scroll the app row to More → Edit and drag ToriWords to the top. | В меню «Поделиться» прокрутите ряд приложений до «Ещё» → «Изменить» и перетащите ToriWords наверх. |  |
| Not in the dictionary | Нет в словаре |  |
| Phrases | Фразы |  |
| Resume learning | Продолжить изучение |  |
| Save | Сохранить |  |
| Save adds this sentence and source. | Сохранение добавит это предложение и источник. |  |
| Save as | Сохранить как |  |
| Saved | Сохранено |  |
| Sentence (optional) | Предложение (необязательно) |  |
| Source | Источник |  |
| Source title | Название источника |  |
| Tags | Теги |  |
| Tap the word to save | Нажмите на слово, чтобы сохранить | Russian differs from the app (section 7) |
| The dictionary is ready after you open ToriWords once | Словарь станет доступен после первого запуска ToriWords |  |
| Tip: put ToriWords first | Совет: поставьте ToriWords первым |  |
| ToriWords saves English words and phrases | ToriWords сохраняет английские слова и фразы |  |
| Translation | Перевод |  |
| Translation (optional) | Перевод (необязательно) |  |
| Translation · Wiktionary | Перевод · Викисловарь |  |
| Without a translation the word is saved as "Translation pending". | Без перевода слово сохранится с пометкой «Перевод ожидается». |  |
| Word or phrase | Слово или фраза |  |
| work, travel | работа, поездки |  |
| You marked this as known | Вы отметили это слово как известное |  |
| You paused this word | Вы приостановили это слово | Russian differs from the app (section 7) |

## 5. Strings outside the catalogs

These are shown as written in every language.

| Text | Where |
|---|---|
| ToriWords | Home Screen name of the app, the share-menu entry and the widget gallery (display name of all three targets); the Home header, the launch screen's VoiceOver label, the Lock Screen widget title |
| GitHub › | About → Source code |
| Wiktionary · kaikki.org (wiktextract) · CC BY-SA 4.0 | About → Licences, links |
| GRDB.swift — Gwendal Roué · MIT | About → Licences → Libraries |
| ToriWords · Apache 2.0 | About → Licences |
| 3 / 17 | Review header position (numbers only) |
| “{sentence}” | Review card fronts: the sentence in typographic quotes |
| — {source} | sentence source line (Review back, entry) |
| /{ipa}/ | capture sheet IPA line |
| {part of speech} · {definition} | capture sheet translation rows |

Licence texts stay in English. System UI (share sheet, Files picker, notification permission alert, Apple Translation download prompt, widget gallery) is worded by iOS.

## 6. Android strings not used on iOS

Section 5 of [android/docs/copy.md](../../android/docs/copy.md) lists the strings that exist only on Android or replace an iOS string there: launcher and capture entry points, the on-device translation model, Google Drive sync, reminders and the notification, the widget hint, language, export, pronunciation, and About and privacy. None of them are used on iOS. The iOS wording for those features is in section 2 of this file.

## 7. Open questions

**Missing translations.** These entries are in use but have no Russian:

- `%@ %@` (ios/App/Localizable.xcstrings) — renders the English pattern, which has no words; adding a Russian entry identical to the English one would silence the catalog warning.

**Stale keys.** These entries fail the "in use" test. They can be deleted from their catalogs; the `%@` variants were left behind when the code switched the numbers to integer interpolation, and their live `%lld` twins are the ones listed above.

- `%@ +%@` (ios/App/Localizable.xcstrings) — superseded by `%@ +%lld`
- `%@ cards · %@ remembered` (ios/App/Localizable.xcstrings) — superseded by `%lld cards · %lld remembered`
- `%@ cards reviewed · %@ remembered · %@ new words` (ios/App/Localizable.xcstrings) — superseded by `%lld cards reviewed · %lld remembered · %lld new words`
- `%@ new words a day` (ios/App/Localizable.xcstrings) — superseded by `%lld new words a day`
- `%@ selected` (ios/App/Localizable.xcstrings) — superseded by `%lld selected`
- `%@ unsynced changes will be lost.` (ios/App/Localizable.xcstrings) — superseded by `%lld unsynced changes will be lost.`
- `%@ words` (ios/App/Localizable.xcstrings) — superseded by `%lld words`
- `%@ words need a translation` (ios/App/Localizable.xcstrings) — superseded by `%lld words need a translation`
- `%@ words were deleted earlier and were not restored.` (ios/App/Localizable.xcstrings) — superseded by `%lld words were deleted earlier and were not restored.`
- `Adds tags to %@ words. Tags they already have stay.` (ios/App/Localizable.xcstrings) — superseded by `Adds tags to %lld words. Tags they already have stay.`
- `Back` (ios/App/Localizable.xcstrings)
- `Card %@ of %@` (ios/App/Localizable.xcstrings) — superseded by `Card %lld of %lld`
- `Delete %@ words?` (ios/App/Localizable.xcstrings) — superseded by `Delete %lld words?`
- `Export %@ words` (ios/App/Localizable.xcstrings) — superseded by `Export %lld words`
- `Imported %@ words, %@ merged with existing.` (ios/App/Localizable.xcstrings) — superseded by `Imported %lld words, %lld merged with existing.`
- `It is removed from %@ words. The words stay.` (ios/App/Localizable.xcstrings) — superseded by `It is removed from %lld words. The words stay.`
- `No translation found` (ios/App/Localizable.xcstrings)
- `Practice · %@ / %@` (ios/App/Localizable.xcstrings) — superseded by `Practice · %lld / %lld`
- `Show %@ words` (ios/App/Localizable.xcstrings) — superseded by `Show %lld words`
- `Welcome back — %@ cards are waiting. We'll spread them over about a week.` (ios/App/Localizable.xcstrings) — superseded by `Welcome back — %lld cards are waiting. We'll spread them over about a week.`
- `%@ new` (ios/WidgetExtension/Localizable.xcstrings) — superseded by `%lld new`
- `%@ to review` (ios/WidgetExtension/Localizable.xcstrings) — superseded by `%lld to review`
- `%@ to review · %@ new` (ios/WidgetExtension/Localizable.xcstrings) — superseded by `%lld to review · %lld new`

**Inconsistent Russian between the app and the capture sheet.** The same English string has different Russian text in `ios/App` and `ios/ShareExtension`:

- "You paused this word": app «Вы поставили это слово на паузу», capture sheet «Вы приостановили это слово». Which wording should both use?
- "Tap the word to save": app «Нажмите на слово, чтобы сохранить его», capture sheet «Нажмите на слово, чтобы сохранить». Which wording should both use?

**Straight quotes.** The capture sheet footer "Without a translation the word is saved as "Translation pending"." uses straight quotes in English, against the “ ” convention. Should it use typographic quotes?
