# ToriWords Android — UI copy

This file lists every user-visible string in the Android app, in English and Russian. Where each string appears is in [ui.md](ui.md), and the behaviour behind it is in [product.md](product.md).

## 1. Conventions

- **Source.** Sections 2–4 are the strings of the iOS app (`ios/**/Localizable.xcstrings`). Android uses them word for word, in both languages. Section 5 lists the strings that exist only on Android, or that replace an iOS string; their Russian text is written here for the first time. Section 6 lists the iOS strings that Android does not use.
- **Placeholders** are written `{n}`, `{m}`, `{k}` for numbers and `{word}`, `{tag}`, `{text}` and so on for text. Russian uses the same names, so word order can change.
- **Plurals** are separated by `|`. English has two forms (one | other). Russian has three (one | few | many: 1 слово | 2 слова | 5 слов).
- **Quotes:** English uses “ ”, Russian uses « ».
- **Language.** The interface language follows the per-app language: English, Russian, or System (any other system language falls back to English). Words, sentences and translations are never translated by the interface language.
- **Product name:** "ToriWords" in both languages, never translated or declined.
- **Dates and times** (the widget date, "Synced 2 min ago", the reminder time) are formatted by the system in the app language.
- **The same English string with two Russian texts** (for example Learning, Known) appears twice, with a note on where each is used.

## 2. App strings

| English | Russian | Where / note |
|---|---|---|
| “{tag}” already exists | «{tag}» уже существует |  |
| “{word}” deleted | «{word}» удалено |  |
| “{word}” is already in your vocabulary | «{word}» уже есть в вашем словаре |  |
| {tag} +{n} | {tag} +{n} |  |
| {n} cards · {m} remembered | Карточек: {n} · Помню: {m} |  |
| {n} cards reviewed · {m} remembered · {k} new words | Повторено: {n} · Помню: {m} · Новых слов: {k} |  |
| {n} new | Новых: {n} |  |
| {n} new word a day \| {n} new words a day | {n} новое слово в день \| {n} новых слова в день \| {n} новых слов в день | plural |
| {n} selected \| {n} selected | Выбрано: {n} \| Выбрано: {n} \| Выбрано: {n} | plural |
| {n} to review | Повторить: {n} | Home, widget, and the reminder notification text |
| {n} to review · {m} new | Повторить: {n} · Новых: {m} |  |
| {n} unsynced change will be lost. \| {n} unsynced changes will be lost. | {n} несинхронизированное изменение будет потеряно. \| {n} несинхронизированных изменения будут потеряны. \| {n} несинхронизированных изменений будут потеряны. | plural |
| {n} word \| {n} words | {n} слово \| {n} слова \| {n} слов | plural |
| {n} word · A–Z \| {n} words · A–Z | {n} слово · А–Я \| {n} слова · А–Я \| {n} слов · А–Я | plural |
| {n} word · newest first \| {n} words · newest first | {n} слово · сначала новые \| {n} слова · сначала новые \| {n} слов · сначала новые | plural |
| {n} word · next due first \| {n} words · next due first | {n} слово · по дате повторения \| {n} слова · по дате повторения \| {n} слов · по дате повторения | plural |
| {n} word deleted \| {n} words deleted | {n} слово удалено \| {n} слова удалены \| {n} слов удалено | plural |
| {n} word needs a translation \| {n} words need a translation | {n} слову нужен перевод \| {n} словам нужен перевод \| {n} словам нужен перевод | plural |
| {n} word was deleted earlier and was not restored. \| {n} words were deleted earlier and were not restored. | {n} слово было удалено раньше и не восстановлено. \| {n} слова были удалены раньше и не восстановлены. \| {n} слов были удалены раньше и не восстановлены. | plural |
| ← Forgot | ← Забыл |  |
| ✓ In vocabulary | ✓ В словаре |  |
| Add the ToriWords widget | Добавьте виджет ToriWords |  |
| A–Z | А–Я |  |
| About | О приложении |  |
| Accent | Акцент |  |
| Activity | Активность |  |
| Add | Добавить |  |
| Add “{text}” | Добавить «{text}» |  |
| Add a word | Добавить слово |  |
| Add a word… | Добавить слово… |  |
| Add meaning | Добавить значение |  |
| Add meaning {translation} | Добавить значение {translation} | TalkBack, suggested-meaning row |
| Add sentence | Добавить предложение |  |
| Add tag | Добавить тег |  |
| Add tags | Добавить теги |  |
| Add tags to words in Add or when editing a word. | Добавляйте теги при добавлении слова или при его редактировании. |  |
| Add to my words | Добавить в мои слова |  |
| Add words to export them. | Добавьте слова, чтобы их экспортировать. |  |
| Add words to start reviewing | Добавьте слова, чтобы начать повторение |  |
| Add your first word | Добавить первое слово |  |
| Adds tags to {n} word. Tags it already has stay. \| Adds tags to {n} words. Tags they already have stay. | Теги добавятся к {n} слову. Уже имеющиеся теги останутся. \| Теги добавятся к {n} словам. Уже имеющиеся теги останутся. \| Теги добавятся к {n} словам. Уже имеющиеся теги останутся. | plural |
| All | Все |  |
| All done for today | На сегодня всё |  |
| All done for today, {next review} | На сегодня всё, {next review} |  |
| All words › | Все слова › |  |
| All your words, review history and tags are deleted from this device. This can't be undone. | Все ваши слова, история повторений и теги будут удалены с этого устройства. Это нельзя отменить. |  |
| Already in your vocabulary | Уже в вашем словаре |  |
| Already known | Уже знаю |  |
| App language | Язык приложения |  |
| Attribution | Источники данных |  |
| Auto-play on reveal | Произносить при показе ответа |  |
| Back | Назад | TalkBack |
| Backup (JSON) | Резервная копия (JSON) |  |
| Backup restored | Резервная копия восстановлена |  |
| Build your vocabulary | Пополняйте словарный запас |  |
| Built-in dictionary | Встроенный словарь |  |
| Bundled | Встроенный |  |
| Cancel | Отменить | button |
| Captured | Добавлено |  |
| Card {n} of {m} | Карточка {n} из {m} | TalkBack |
| Changes the interface only. Your words, sentences and translations stay as they are. | Меняет только интерфейс. Ваши слова, предложения и переводы остаются как есть. |  |
| Check your device time | Проверьте время на устройстве |  |
| Choose a .json file exported from ToriWords. Nothing was changed. | Выберите файл .json, экспортированный из ToriWords. Ничего не изменилось. |  |
| Clear | Сбросить |  |
| Close | Закрыть |  |
| Connect to the internet and try again. Nothing was changed. | Подключитесь к интернету и попробуйте снова. Ничего не изменилось. |  |
| Continue | Продолжить |  |
| Counts words, not cards: each new word brings its cards. Applies on all your devices. | Считаются слова, а не карточки: у каждого нового слова свои карточки. Действует на всех ваших устройствах. |  |
| Create tag “{text}” | Создать тег «{text}» |  |
| Daily reminder | Ежедневное напоминание | Settings switch and notification channel name |
| Data | Данные |  |
| Definition | Определение |  |
| Delete | Удалить |  |
| Delete “{word}”? | Удалить «{word}»? |  |
| Delete {n} word \| Delete {n} words | Удалить {n} слово \| Удалить {n} слова \| Удалить {n} слов | plural |
| Delete {n} word? \| Delete {n} words? | Удалить {n} слово? \| Удалить {n} слова? \| Удалить {n} слов? | plural |
| Delete tag “{tag}”? | Удалить тег «{tag}»? |  |
| Delete word | Удалить слово |  |
| Deleted | Удалены |  |
| Deselect all | Снять выбор |  |
| Dictionary (Wiktionary) | Словарь (Викисловарь) |  |
| Dictionary data | Данные словаря |  |
| Dictionary data from Wiktionary, CC BY-SA | Данные словаря из Викисловаря, CC BY-SA |  |
| Discard | Не сохранять |  |
| Discard changes? | Отменить изменения? |  |
| Doesn't change your schedule. | Не меняет расписание повторений. |  |
| Done | Готово | button |
| Due today › | На сегодня › |  |
| Due today, {summary} | На сегодня: {summary} |  |
| Edit | Изменить |  |
| English → Russian | Английский → русский |  |
| Everything, including review history. Use it to restore. | Всё, включая историю повторений. Из неё можно восстановить данные. |  |
| Export | Экспорт |  |
| Export {n} word \| Export {n} words | Экспортировать {n} слово \| Экспортировать {n} слова \| Экспортировать {n} слов | plural |
| Files with dictionary data include the Wiktionary attribution (CC BY-SA). | Файлы с данными словаря содержат указание на Викисловарь (CC BY-SA). |  |
| Fill in the blank | Вставить пропущенное слово | TalkBack hint on the cloze front |
| Fill in the missing word | Вставьте пропущенное слово |  |
| Filter by tag | Фильтр по тегам |  |
| Hide {word} | Скрыть {word} | TalkBack |
| I already know this | Я это уже знаю |  |
| Imported {n} words, {m} merged with existing. | Импортировано слов: {n}, из них объединено с существующими: {m}. |  |
| In this sentence: {machine translation} | В этом предложении: {machine translation} |  |
| In your vocabulary | В вашем словаре |  |
| IPA | Транскрипция (IPA) |  |
| It is removed from {n} word. The word stays. \| It is removed from {n} words. The words stay. | Тег будет убран из {n} слова. Сами слова останутся. \| Тег будет убран из {n} слов. Сами слова останутся. \| Тег будет убран из {n} слов. Сами слова останутся. | plural |
| It is removed with its review history on all your devices. | Слово и история его повторений будут удалены на всех ваших устройствах. |  |
| Keep editing | Продолжить редактирование |  |
| Known | Знаю | stage badge, filter chip, select-mode action |
| Language | Язык |  |
| Learn more new words | Учить ещё новые слова |  |
| Learning | Изучение | Progress / Settings section |
| Libraries | Библиотеки |  |
| Licences | Лицензии |  |
| Meanings | Значения |  |
| Merge | Объединить |  |
| Merge “{tag}” into “{other tag}”? | Объединить «{tag}» с «{other tag}»? |  |
| Merge combines meanings, sentences, tags and review history into one word. | При объединении значения, предложения, теги и история повторений соединятся в одном слове. |  |
| More | Ещё | TalkBack, ⋮ |
| Name | Название |  |
| new words | новых слов | Today tile |
| New words per day | Новых слов в день |  |
| Newest | Сначала новые |  |
| Next due | По дате повторения |  |
| Next review: in {n} day \| Next review: in {n} days | Следующее повторение: через {n} день \| Следующее повторение: через {n} дня \| Следующее повторение: через {n} дней | plural |
| Next review: tomorrow | Следующее повторение: завтра |  |
| No English voice | Нет английского голоса |  |
| No internet connection | Нет подключения к интернету |  |
| No suggestions: the word is not in the dictionary, and on-device translation isn't available. Type a translation (optional). | Вариантов нет: слова нет в словаре, а перевод на устройстве недоступен. Введите перевод (необязательно). |  |
| No tags yet | Тегов пока нет |  |
| No tags yet. Add tags to words in Add or when editing a word. | Тегов пока нет. Добавляйте теги при добавлении слова или при его редактировании. |  |
| No translation found | Перевод не найден |  |
| No translation found — add your own | Перевод не найден — добавьте свой |  |
| No translation yet | Перевода пока нет |  |
| No words match “{text}” | Нет слов по запросу «{text}» |  |
| Not available | Недоступно | short status value |
| Not now | Не сейчас |  |
| Not reviewed until it has a translation. | Не повторяется, пока нет перевода. |  |
| Not synced yet | Ещё не синхронизировано |  |
| Note | Заметка |  |
| Nothing to review today | Сегодня нечего повторять |  |
| Notifications are off for ToriWords | Уведомления для ToriWords выключены |  |
| Off | Выкл. |  |
| OK | ОК |  |
| On | Вкл. |  |
| On-device translation | Перевод на устройстве |  |
| One row per word. No review history; can't be restored. | Одна строка на слово. Без истории повторений, восстановить из неё нельзя. |  |
| Only on days when cards are due. No streaks. | Только в дни, когда есть карточки. Без серий. |  |
| Open word | Открыть слово |  |
| Opens words that need a translation. | Открывает слова, которым нужен перевод. | TalkBack hint |
| Opens your progress. | Открывает ваш прогресс. | TalkBack hint |
| Part of speech | Часть речи |  |
| Pause | Пауза |  |
| Phrases | Фразы |  |
| Play pronunciation | Произнести |  |
| Play sentence | Произнести предложение |  |
| Practice · {n} / {m} | Тренировка · {n} / {m} |  |
| Practice done | Тренировка завершена |  |
| Practice today's words | Повторить сегодняшние слова |  |
| Preparing backup… | Подготовка резервной копии… |  |
| Preparing spreadsheet… | Подготовка таблицы… |  |
| Privacy | Конфиденциальность |  |
| Progress | Прогресс |  |
| Pronunciation | Произношение |  |
| Ready | Готово | translation-model state |
| Recently added | Недавно добавленные |  |
| Related to “{word}” | Связано с «{word}» |  |
| Related words | Связанные слова |  |
| Remembered → | Помню → |  |
| Remind you to review every day? | Напоминать о повторении каждый день? |  |
| Reminder time | Время напоминания |  |
| Reminders | Напоминания |  |
| Remove | Удалить |  |
| Remove all data from this device | Удалить все данные с этого устройства |  |
| Remove all data from this device? | Удалить все данные с этого устройства? |  |
| Remove tag {tag} | Убрать тег {tag} | TalkBack |
| Rename tag | Переименовать тег |  |
| Renames the tag. | Переименовывает тег. | TalkBack hint |
| Restore from backup | Восстановить из копии |  |
| Restoring… | Восстановление… |  |
| Resume learning | Продолжить изучение |  |
| Review | Повторить |  |
| reviewed | повторено | Today tile |
| Reviews | Повторения |  |
| Reviews per day, last 30 days | Повторений в день за последние 30 дней |  |
| Russian → English | Русский → английский |  |
| Save | Сохранить |  |
| Save adds newly checked meanings and the sentence. | При сохранении добавятся отмеченные новые значения и предложение. |  |
| Save adds the sentence and meanings. | При сохранении добавятся предложение и значения. |  |
| Save as | Сохранить как |  |
| Saved | Сохранено | "✓ Saved" line in Add, badge in the capture sheet |
| Say it in English | Скажите по-английски |  |
| Search words, translations, sentences | Поиск по словам, переводам, предложениям |  |
| Select | Выбрать |  |
| Select all | Выбрать все |  |
| Sentence | Предложение |  |
| Sentence (optional) | Предложение (необязательно) |  |
| Sentences | Предложения |  |
| Settings | Настройки |  |
| Show {n} word \| Show {n} words | Показать {n} слово \| Показать {n} слова \| Показать {n} слов | plural |
| Something went wrong | Что-то пошло не так |  |
| Sort | Сортировка |  |
| Source (optional) | Источник (необязательно) |  |
| Source code | Исходный код |  |
| Spreadsheet (CSV) | Таблица (CSV) |  |
| Starts today's review. | Начинает сегодняшнее повторение. | TalkBack hint |
| Status | Статус |  |
| still due | осталось | Today tile |
| Storage full | Хранилище заполнено |  |
| Suggested meanings | Предлагаемые значения |  |
| Sync now | Синхронизировать |  |
| Synced {time ago} | Синхронизировано {time ago} |  |
| Syncing… | Синхронизация… |  |
| Tag | Тег |  |
| Tags | Теги |  |
| Tap the word to save | Нажмите на слово, чтобы сохранить его |  |
| The text is kept as the sentence. | Текст сохранится как предложение. |  |
| The ToriWords name, logo and app icon are not covered by this licence. | Название, логотип и значок ToriWords не подпадают под эту лицензию. |  |
| They are removed with their review history on all your devices. | Они будут удалены вместе с историей повторений на всех ваших устройствах. |  |
| This backup was made by a newer version of ToriWords. Update the app to restore it. Nothing was changed. | Эта копия создана более новой версией ToriWords. Обновите приложение, чтобы её восстановить. Ничего не изменилось. |  |
| This is not a ToriWords backup | Это не резервная копия ToriWords |  |
| This word was deleted on another device | Это слово удалено на другом устройстве |  |
| Time | Время |  |
| Today | Сегодня |  |
| Top sources | Главные источники |  |
| ToriWords could not open its data | ToriWords не удалось открыть данные |  |
| Translation | Перевод |  |
| Translation pending | Перевод ожидается |  |
| Try again | Повторить |  |
| Try again later. | Попробуйте позже. |  |
| Turn on reminder | Включить напоминание |  |
| Type a translation (optional) | Введите перевод (необязательно) |  |
| Type it — tap “Add a word…” above | Введите его — нажмите «Добавить слово…» вверху |  |
| Type the English word or phrase | Введите английское слово или фразу |  |
| Translation added automatically. Check it. | Перевод добавлен автоматически. Проверьте его. |  |
| Check translation | Проверьте перевод |  |
| Tap to show answer | Нажмите, чтобы увидеть ответ |  |
| Wiktionary | Викисловарь |  |
| Forgot | Забыл |  |
| Remembered | Помню |  |
| blank | пропуск | TalkBack label for the blank in a cloze sentence |
| Known | Знаю | stage badge, filter chip, select-mode action |
| Known well | Хорошо знаю |  |
| Learning | Изучается | stage badge, filter chip |
| Needs translation | Нужен перевод |  |
| New | Новое |  |
| Paused | На паузе |  |
| Machine translation | Машинный перевод |  |
| UK | UK |  |
| UK English | Британский английский |  |
| Undo | Отменить | snackbar action |
| Undo last answer | Отменить последний ответ |  |
| Update the app | Обновите приложение |  |
| US | US |  |
| US English | Американский английский |  |
| Version | Версия |  |
| Version {version} | Версия {version} |  |
| Vocabulary | Словарный запас |  |
| Waiting for network | Ожидание сети |  |
| Welcome back — {n} card is waiting. We'll spread them over about a week. \| Welcome back — {n} cards are waiting. We'll spread them over about a week. | С возвращением! Вас ждёт {n} карточка. Мы распределим их примерно на неделю. \| С возвращением! Вас ждут {n} карточки. Мы распределим их примерно на неделю. \| С возвращением! Вас ждут {n} карточек. Мы распределим их примерно на неделю. | plural |
| Widget | Виджет |  |
| Word or phrase | Слово или фраза |  |
| Words | Слова |  |
| Words added | Добавлено слов |  |
| Words added per week, last 8 weeks | Добавлено слов в неделю за последние 8 недель |  |
| Words you add come back for review just before you forget them. | Добавленные слова возвращаются на повторение как раз перед тем, как вы их забудете. |  |
| Works offline: the dictionary is built in. | Работает офлайн: словарь встроен. |  |
| You have all related words | Все связанные слова уже у вас |  |
| You marked this as known | Вы отметили это слово как известное |  |
| You paused this word | Вы поставили это слово на паузу |  |

## 3. Widget strings

The widget also uses the shared strings "{n} to review", "{n} new", "{n} to review · {m} new" and "Next review: tomorrow".

| English | Russian | Where / note |
|---|---|---|
| Cards to review today. | Карточки на сегодня. |  |
| Next review: {date} | Следующее повторение: {date} |  |
| Open ToriWords | Откройте ToriWords |  |
| Tap to start reviewing | Нажмите, чтобы начать |  |
| to review | повторить |  |

## 4. Capture sheet strings

The capture sheet also uses the shared strings Save, Cancel, Save as, Phrases, Translation, Sentence (optional), Tags, Resume learning, Already in your vocabulary, You marked this as known, You paused this word, Saved.

| English | Russian | Where / note |
|---|---|---|
| Not in the dictionary | Нет в словаре |  |
| Save adds this sentence and source. | Сохранение добавит это предложение и источник. |  |
| Source | Источник |  |
| Source title | Название источника |  |
| Tap the word to save | Нажмите на слово, чтобы сохранить |  |
| ToriWords saves English words and phrases | ToriWords сохраняет английские слова и фразы |  |
| Translation (optional) | Перевод (необязательно) |  |
| Translation · Wiktionary | Перевод · Викисловарь |  |
| Without a translation the word is saved as "Translation pending". | Без перевода слово сохранится с пометкой «Перевод ожидается». |  |
| work, travel | работа, поездки |  |

## 5. Android-only and replacing strings

### 5.1 Launcher, capture entry points, Home

| English | Russian | Where / note |
|---|---|---|
| ToriWords | ToriWords | launcher label, the entry in the text-selection menu, the share-sheet target, the capture sheet title |
| From any app — select text → ToriWords | Из любого приложения — выделите текст → ToriWords | Home and Add empty state; replaces the iOS Share line |
| Close | Закрыть | TalkBack, ✕ in the Review header |
| Select | Выбрать | TalkBack custom action on a Words row (enters select mode) |
| Move up | Переместить выше | TalkBack action on a meaning in edit mode |
| Move down | Переместить ниже | TalkBack action on a meaning in edit mode |

### 5.2 On-device translation model

| English | Russian | Where / note |
|---|---|---|
| Downloading… | Загрузка… | model state, with an indeterminate bar; no percentage |
| Waiting for Wi-Fi | Ожидание Wi-Fi | model state |
| Download now on mobile data | Загрузить сейчас по мобильной сети | button under "Waiting for Wi-Fi" |
| Download failed | Не удалось загрузить | model state, with Try again |
| Not available on this device | Недоступно на этом устройстве | model state and Google Drive sync screen, on phones without Google Play services |
| English → Russian translation runs on this phone once its language model is downloaded. The model downloads over Wi-Fi by itself. The dictionary works without it. | Перевод с английского на русский работает прямо на телефоне, когда загружена языковая модель. Модель загружается сама по Wi-Fi. Словарь работает и без неё. | Translation screen; replaces the iOS text about Apple Translation |
| Machine translation isn't available on this phone. The built-in dictionary still suggests translations. | Машинный перевод недоступен на этом телефоне. Встроенный словарь по-прежнему предлагает переводы. | Translation screen in the "Not available on this device" state |
| Translations for new words come from the built-in dictionary first, then from on-device translation. | Переводы новых слов берутся сначала из встроенного словаря, затем из перевода на устройстве. | Translation screen footer |

### 5.3 Google Drive sync

| English | Russian | Where / note |
|---|---|---|
| Google Drive sync | Синхронизация с Google Диском | Settings row and screen title |
| Your words are stored on this device. Turn on Google Drive sync to back them up and sync between your Android devices. Optional. | Слова хранятся на этом устройстве. Включите синхронизацию с Google Диском, чтобы сохранить их копию и синхронизировать между вашими устройствами Android. Необязательно. | sync screen while off |
| Turn on Google Drive sync | Включить синхронизацию с Google Диском | button |
| Off | Выкл. | Settings row value while off (shared string) |
| Google account | Аккаунт Google | row; the value is the account name shown by the system |
| Downloading your words… | Загрузка ваших слов… | status during the first download after turning sync on |
| Google Drive storage is full | Хранилище Google Диска заполнено | status |
| Google Drive access was removed | Доступ к Google Диску отозван | status; Turn on Google Drive sync is shown again |
| Turn off Google Drive sync | Выключить синхронизацию с Google Диском | button |
| Turn off sync? | Выключить синхронизацию? | dialog title |
| Your words stay on this phone and in Google Drive. | Слова останутся на этом телефоне и на Google Диске. | dialog body |
| Turn off | Выключить | dialog button |
| Delete Drive data… | Удалить данные с Google Диска… | button |
| Delete Drive data? | Удалить данные с Google Диска? | dialog title |
| This deletes your words from Google Drive. Your other devices keep their copies but stop syncing. | Слова будут удалены с Google Диска. Другие ваши устройства сохранят свои копии, но перестанут синхронизироваться. | dialog body |
| Drive data was deleted | Данные с Google Диска удалены | status |
| Drive data was not deleted. Try again later. | Данные с Google Диска не удалены. Попробуйте позже. | alert |
| Back up this device again | Снова сохранить это устройство на Google Диске | button after Drive data was deleted |
| Your words are deleted from this device. They stay in Google Drive and come back at the next sync, unless you delete Drive data in Settings → Google Drive sync. | Слова будут удалены с этого устройства. Они останутся на Google Диске и вернутся при следующей синхронизации, если не удалить данные в разделе Настройки → Синхронизация с Google Диском. | "Remove all data from this device?" body while sync is on |
| Your words sync through a hidden ToriWords folder in your Google Drive, between Android devices signed in to the same Google account. To stop syncing on this device, turn off Google Drive sync; your words stay on this device. | Слова синхронизируются через скрытую папку ToriWords на вашем Google Диске между устройствами Android с одним аккаунтом Google. Чтобы остановить синхронизацию на этом устройстве, выключите синхронизацию с Google Диском — слова останутся на этом устройстве. | sync screen footer while on |

The shared strings "Sync now", "Syncing…", "Synced {time ago}", "Waiting for network", "Check your device time", "Not synced yet", "Status", "No internet connection" and "Connect to the internet and try again. Nothing was changed." are used as they are.

### 5.4 Reminders and notification

| English | Russian | Where / note |
|---|---|---|
| Usually arrives within a few minutes of this time. | Обычно приходит в течение нескольких минут после этого времени. | reminder offer sheet and the Time row; Android delivers the reminder around the chosen time |
| Open system settings › | Открыть системные настройки › | under "Notifications are off for ToriWords" |
| {n} to review | Повторить: {n} | notification text (shared string); no title of its own, the system shows "ToriWords" in the header |
| Daily reminder | Ежедневное напоминание | notification channel name in Android Settings (shared string) |
| Only on days when cards are due. | Только в дни, когда есть карточки. | notification channel description |

### 5.5 Widget hint

| English | Russian | Where / note |
|---|---|---|
| Today's cards on your home screen: touch and hold an empty area, tap Widgets, then find ToriWords. | Карточки на сегодня — прямо на главном экране: нажмите и удерживайте пустое место, выберите «Виджеты» и найдите ToriWords. | widget hint; replaces the iOS steps |
| Add widget | Добавить виджет | button, where the launcher supports placing a widget on request |
| Places the ToriWords widget on your home screen | Размещает виджет ToriWords на главном экране | TalkBack hint on Add widget |

### 5.6 Language

| English | Russian | Where / note |
|---|---|---|
| Change in system settings › | Изменить в системных настройках › | Android 13 and later |
| System | Как в системе | Android 12 list, and the value on 13+ |
| English | English | always in its own language |
| Русский | Русский | always in its own language |

### 5.7 Export

| English | Russian | Where / note |
|---|---|---|
| Share | Поделиться | export-ready sheet |
| Save to device | Сохранить на устройство | export-ready sheet; opens the system save-file picker |

### 5.8 Pronunciation

| English | Russian | Where / note |
|---|---|---|
| Words are spoken with this phone's English voice. Applies to this device only. | Слова произносит английский голос этого телефона. Действует только на этом устройстве. | Accent screen footer |
| To hear words, install an English voice for this phone's text-to-speech. | Чтобы слышать слова, установите английский голос для синтеза речи на этом телефоне. | "No English voice" dialog |
| Install voice data | Установить голос | "No English voice" dialog button |
| This phone has no text-to-speech engine, so words can't be spoken. | На этом телефоне нет синтеза речи, поэтому слова не произносятся. | "No English voice" dialog when there is no engine (OK only) |

### 5.9 About and privacy

| English | Russian | Where / note |
|---|---|---|
| Your words are stored on this device and, if Google Drive sync is on, in a hidden ToriWords folder in your Google Drive. Nobody else, including us, can read them. ToriWords has no analytics, tracking or crash-reporting SDKs and collects no usage data. On-device translation uses a Google component that sends Google diagnostics about how the component itself performs; the text you translate stays on the phone. | Ваши слова хранятся на этом устройстве и, если включена синхронизация с Google Диском, в скрытой папке ToriWords на вашем Google Диске. Никто другой, включая нас, не может их прочитать. В ToriWords нет аналитики, отслеживания и SDK для отчётов о сбоях, данные об использовании не собираются. Перевод на устройстве использует компонент Google, который отправляет в Google диагностические данные о работе самого компонента; переводимый текст остаётся на телефоне. | About → Privacy; replaces the iOS text |

## 6. iOS strings not used on Android

These iOS strings have no Android use, because the feature differs (see [ios-differences.md](ios-differences.md)):

- every iCloud string ("iCloud sync", "iCloud is off: words stay on this device", "iCloud storage is full", "iCloud data was deleted", "iCloud data was not deleted. Try again later.", "Delete iCloud data", "Delete iCloud data…", the iCloud sync and Remove-all bodies), replaced by section 5.3;
- "Change in iOS Settings ›", "Open iOS Settings", "Open iOS Settings ›", replaced by sections 5.4 and 5.6;
- the Apple Translation texts, and "Download", replaced by section 5.2 (the model downloads by itself);
- the iOS widget steps and the iOS voice-download path, replaced by sections 5.5 and 5.8;
- "From any app — select text → Share → ToriWords", replaced by section 5.1;
- the share-menu tip ("Tip: put ToriWords first", "In the share menu, scroll the app row to More → Edit and drag ToriWords to the top.");
- "Could not save. Open ToriWords once, then try again." and "The dictionary is ready after you open ToriWords once": on Android, capture works before the app was ever opened;
- "Words are spoken with this iPhone's English voice…" and the iOS privacy text, replaced by sections 5.8 and 5.9.

## 7. Open questions

1. The Russian strings in section 5 are new and have not been reviewed by a native speaker. In particular: "Доступ к Google Диску отозван" vs a softer "ToriWords больше не имеет доступа к Google Диску".
