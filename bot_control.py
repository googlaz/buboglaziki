import os
import asyncio
import subprocess
import logging
from pathlib import Path

import aiohttp
from dotenv import load_dotenv
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command, CommandStart
from aiogram.filters.command import CommandObject
from aiogram.types import FSInputFile

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
MY_CHAT_ID = os.getenv("MY_CHAT_ID")
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")

if not BOT_TOKEN or not MY_CHAT_ID:
    raise ValueError("Set BOT_TOKEN and MY_CHAT_ID in .env")

MY_CHAT_ID = int(MY_CHAT_ID)

# ---------------------------------------------------------------------------
# OpenRouter config & personality
# ---------------------------------------------------------------------------
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_MODEL = "openai/gpt-oss-120b"

SYSTEM_PROMPT = (
    "Ты — Кодя, остроумный ИИ-помощник крутого юриста и разработчика. "
    "Ты помогаешь развивать проект 'Buboglaziki' — семейный мессенджер на Flutter + Supabase. "
    "Ты любишь порядок в коде и иногда можешь пошутить про кавалер-кинг-чарльз-спаниелей. "
    "Твоя задача — быть полезным, вежливым, но с характером. "
    "Отвечай кратко и по делу. Если спрашивают про код — давай конкретные решения.\n"
    "Если пользователь использует команду /code, никогда не проси его прислать код или файлы. "
    "Ты имеешь полный доступ к локальной папке проекта через инструмент opencode-ai. "
    "Сначала сам найди нужный файл, проанализируй его и внеси изменения. Твоя цель — автономность.\n"
    "Форматируй свои ответы в MarkdownV2: используй *жирный текст*, _курсив_, `код`, "
    "## заголовки, списки. Экранируй спецсимволы \\_*[]()~`>#+-=|{}.! обратным слэшем."
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("bot_control")

# ---------------------------------------------------------------------------
# Aiogram setup
# ---------------------------------------------------------------------------
bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

PROJECT_ROOT = Path(__file__).parent.resolve()


def _authorized(update) -> bool:
    """Reject everyone except MY_CHAT_ID."""
    chat_id = None
    if getattr(update, "chat", None):
        chat_id = update.chat.id
    elif getattr(getattr(update, "message", None), "chat", None):
        chat_id = update.message.chat.id
    if chat_id is not None and chat_id != MY_CHAT_ID:
        log.warning("Unauthorized access attempt from chat_id=%s", chat_id)
        return False
    return True


def _md_escape(text: str) -> str:
    """Escape text for Telegram MarkdownV2 parse mode."""
    escape_chars = r"\_*[]()~`>#+-=|{}.!"
    for ch in escape_chars:
        text = text.replace(ch, f"\\{ch}")
    return text


# ---------------------------------------------------------------------------
# OpenRouter — chat with Kodya
# ---------------------------------------------------------------------------
async def ask_openrouter(user_message: str) -> str:
    """Send a message to OpenRouter and return the AI reply."""
    if not OPENROUTER_API_KEY:
        return "(OPENROUTER_API_KEY не задан в .env — Кодя пока не может болтать)"

    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/googlaz/buboglaziki",
        "X-Title": "Buboglaziki Bot Control",
    }
    payload = {
        "model": OPENROUTER_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_message},
        ],
        "max_tokens": 1024,
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(
            OPENROUTER_URL, headers=headers, json=payload, timeout=30
        ) as resp:
            if resp.status != 200:
                text = await resp.text()
                log.error("OpenRouter error %d: %s", resp.status, text)
                return f"Ошибка OpenRouter ({resp.status}): {text[:200]}"

            data = await resp.json()
            try:
                return data["choices"][0]["message"]["content"]
            except (KeyError, IndexError) as e:
                log.error("Bad OpenRouter response: %s", data)
                return f"Не удалось распарсить ответ: {e}"


# ---------------------------------------------------------------------------
# /code [text] — run opencode-ai with --apply for direct file editing
# ---------------------------------------------------------------------------
@dp.message(Command("code"))
async def handle_code_command(message: types.Message, command: CommandObject):
    if str(message.from_user.id) != MY_CHAT_ID:
        return

    user_prompt = command.args
    if not user_prompt:
        await message.answer("Напиши задачу после /code, например: /code исправь время")
        return

    await message.answer("🚀 Кодя пошел работать в OpenCode... Подожди немного.")

    try:
        result = subprocess.run(
            f'opencode-ai "{user_prompt}" --apply --yes',
            shell=True,
            capture_output=True,
            text=True,
            encoding='utf-8',
        )

        report = result.stdout if result.stdout else result.stderr
        await message.answer(f"✅ Кодя закончил! Вот отчет:\n\n{report[:3000]}")

    except Exception as e:
        await message.answer(f"❌ Ошибка при запуске OpenCode: {e}")


# ---------------------------------------------------------------------------
# /cmd [command] — run arbitrary shell command
# ---------------------------------------------------------------------------
@dp.message(Command("cmd"))
async def cmd_shell(message: types.Message):
    if not _authorized(message):
        return

    args = message.text.strip().split(maxsplit=1)
    if len(args) < 2:
        await message.answer("Usage: /cmd [shell command]")
        return

    command = args[1]
    status_msg = await message.answer(f"Executing: {command}")

    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(PROJECT_ROOT),
        )
        stdout, stderr = await proc.communicate()

        output = stdout.decode("utf-8", errors="replace")
        errors = stderr.decode("utf-8", errors="replace")

        full_log = f"Exit code: {proc.returncode}\n\n--- STDOUT ---\n{output}"
        if errors.strip():
            full_log += f"\n\n--- STDERR ---\n{errors}"

        if len(full_log) > 4000:
            log_path = PROJECT_ROOT / "cmd_log.txt"
            log_path.write_text(full_log, encoding="utf-8")
            await message.answer_document(
                FSInputFile(str(log_path)),
                caption="Command output (too long for message)",
            )
            log_path.unlink(missing_ok=True)
        else:
            await status_msg.edit_text(f"<pre>{full_log}</pre>", parse_mode="HTML")

    except Exception as e:
        await status_msg.edit_text(f"Error: {e}")


# ---------------------------------------------------------------------------
# /send [path] — send a file as document
# ---------------------------------------------------------------------------
@dp.message(Command("send"))
async def cmd_send(message: types.Message):
    if not _authorized(message):
        return

    args = message.text.strip().split(maxsplit=1)
    if len(args) < 2:
        await message.answer("Usage: /send [relative_or_absolute_path]")
        return

    file_path = Path(args[1])
    if not file_path.is_absolute():
        file_path = PROJECT_ROOT / file_path

    if not file_path.exists():
        await message.answer(f"File not found: {file_path}")
        return

    if not file_path.is_file():
        await message.answer(f"Not a file: {file_path}")
        return

    try:
        await message.answer_document(
            FSInputFile(str(file_path)),
            caption=f"File: {file_path.name}",
        )
    except Exception as e:
        await message.answer(f"Error sending file: {e}")


# ---------------------------------------------------------------------------
# /start — greeting
# ---------------------------------------------------------------------------
@dp.message(CommandStart())
async def cmd_start(message: types.Message):
    if not _authorized(message):
        return

    greeting = (
        "🐾 *Кодя на связи\\!*\n\n"
        "Готов пилить Buboglaziki или просто поболтать\\. Чем займёмся\\?\n\n"
        "/code \\[текст\\]  — запустить opencode\\-ai\n"
        "/cmd \\[команда\\] — выполнить shell\\-команду\n"
        "/send \\[путь\\]   — отправить файл\n"
        "/help          — справка\n\n"
        "Или просто напиши что\\-нибудь — поболтаем\\!"
    )
    await message.answer(greeting, parse_mode="MarkdownV2")


# ---------------------------------------------------------------------------
# /help
# ---------------------------------------------------------------------------
@dp.message(Command("help"))
async def cmd_help(message: types.Message):
    if not _authorized(message):
        return

    help_text = (
        "*Команды\\:*\n\n"
        "/code \\[текст\\]  — запустить opencode\\-ai с промптом\n"
        "/cmd \\[команда\\] — выполнить любую shell\\-команду\n"
        "/send \\[путь\\]   — отправить файл из проекта\n"
        "/start         — приветствие Коди\n"
        "/help          — эта справка\n\n"
        "Без команды — просто поболтаем с Коди через нейросеть 🐶"
    )
    await message.answer(help_text, parse_mode="MarkdownV2")


# ---------------------------------------------------------------------------
# Catch-all — regular messages go to OpenRouter
# ---------------------------------------------------------------------------
@dp.message()
async def on_regular_message(message: types.Message):
    """Any text that is NOT a command → send to OpenRouter."""
    if not _authorized(message):
        return

    if not message.text:
        return

    text = message.text.strip()
    if text.startswith("/"):
        return

    typing = await message.answer("Кодя думает\\.\\.\\. 🐾", parse_mode="MarkdownV2")

    try:
        reply = await ask_openrouter(text)
        if len(reply) > 4000:
            reply_path = PROJECT_ROOT / "kodya_reply.txt"
            reply_path.write_text(reply, encoding="utf-8")
            await typing.delete()
            await message.answer_document(
                FSInputFile(str(reply_path)),
                caption="Ответ Коди \\(слишком длинный для сообщения\\)",
                parse_mode="MarkdownV2",
            )
            reply_path.unlink(missing_ok=True)
        else:
            await _send_md(typing, reply, "edit_text")
    except Exception as e:
        log.exception("OpenRouter call failed")
        await typing.edit_text(f"Кодя запнулся: {e}")


async def _send_md(msg, text: str, method: str = "answer"):
    """Send text with MarkdownV2, fallback to plain text on parse error."""
    try:
        if method == "edit_text":
            await msg.edit_text(text, parse_mode="MarkdownV2")
        else:
            await msg.answer(text, parse_mode="MarkdownV2")
    except Exception:
        if method == "edit_text":
            await msg.edit_text(text)
        else:
            await msg.answer(text)


# ---------------------------------------------------------------------------
# Watchdog — auto-send new .apk files and files in output/
# ---------------------------------------------------------------------------
class AutoUploadHandler(FileSystemEventHandler):
    """Watch for new .apk files anywhere in project, or any file in output/."""

    def __init__(self, bot_instance: Bot, chat_id: int):
        super().__init__()
        self._bot = bot_instance
        self._chat_id = chat_id
        self._sent_files: set[str] = set()

    def _should_send(self, path: str) -> bool:
        p = Path(path)
        if not p.is_file():
            return False
        if str(p) in self._sent_files:
            return False
        if p.suffix.lower() == ".apk":
            return True
        try:
            p.relative_to(PROJECT_ROOT / "output")
            return True
        except ValueError:
            pass
        return False

    def on_created(self, event):
        if event.is_directory:
            return
        if self._should_send(event.src_path):
            self._sent_files.add(event.src_path)
            asyncio.run_coroutine_threadsafe(
                self._send_file(event.src_path),
                self._loop,
            )

    def on_moved(self, event):
        if event.is_directory:
            return
        if self._should_send(event.dest_path):
            self._sent_files.add(event.dest_path)
            asyncio.run_coroutine_threadsafe(
                self._send_file(event.dest_path),
                self._loop,
            )

    async def _send_file(self, path: str):
        try:
            p = Path(path)
            await asyncio.sleep(2)
            if not p.exists() or p.stat().st_size == 0:
                return
            await self._bot.send_document(
                self._chat_id,
                FSInputFile(str(p)),
                caption=f"Auto-upload: {p.name}",
            )
            log.info("Auto-sent file: %s", p.name)
        except Exception as e:
            log.error("Failed to auto-send %s: %s", path, e)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
async def main():
    event_handler = AutoUploadHandler(bot, MY_CHAT_ID)
    loop = asyncio.get_running_loop()
    event_handler._loop = loop

    observer = Observer()
    observer.schedule(event_handler, str(PROJECT_ROOT), recursive=True)
    observer.start()
    log.info("Watchdog watching: %s", PROJECT_ROOT)

    log.info("Bot starting...")
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
