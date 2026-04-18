import os
import asyncio
import subprocess
import logging
from pathlib import Path

from dotenv import load_dotenv
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
from aiogram.types import FSInputFile

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
MY_CHAT_ID = os.getenv("MY_CHAT_ID")

if not BOT_TOKEN or not MY_CHAT_ID:
    raise ValueError("Set BOT_TOKEN and MY_CHAT_ID in .env")

MY_CHAT_ID = int(MY_CHAT_ID)

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


# ---------------------------------------------------------------------------
# /code [text] — run opencode-ai "[text]" and send log
# ---------------------------------------------------------------------------
@dp.message(Command("code"))
async def cmd_code(message: types.Message):
    if not _authorized(message):
        return

    args = message.text.strip().split(maxsplit=1)
    if len(args) < 2:
        await message.answer("Usage: /code [prompt text]")
        return

    prompt = args[1]
    command = f'opencode-ai "{prompt}"'

    status_msg = await message.answer(f"Running: {command}")

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

        # Telegram message limit is 4096 chars
        if len(full_log) > 4000:
            # Send as file
            log_path = PROJECT_ROOT / "opencode_log.txt"
            log_path.write_text(full_log, encoding="utf-8")
            await message.answer_document(
                FSInputFile(str(log_path)),
                caption="opencode-ai log (too long for message)",
            )
            log_path.unlink(missing_ok=True)
        else:
            await status_msg.edit_text(f"<pre>{full_log}</pre>", parse_mode="HTML")

    except Exception as e:
        await status_msg.edit_text(f"Error: {e}")


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
# /start, /help
# ---------------------------------------------------------------------------
@dp.message(Command("start", "help"))
async def cmd_help(message: types.Message):
    if not _authorized(message):
        return

    help_text = (
        "Available commands:\n\n"
        "/code [text]  — run opencode-ai with the given prompt\n"
        "/cmd [cmd]    — execute any shell command\n"
        "/send [path]  — send a file from the project\n"
        "/help         — show this message"
    )
    await message.answer(help_text)


# ---------------------------------------------------------------------------
# Watchdog — auto-send new .apk files and files in output/
# ---------------------------------------------------------------------------
class AutoUploadHandler(FileSystemEventHandler):
    """Watch for new .apk files anywhere in project, or any file in output/."""

    def __init__(self, bot_instance: Bot, chat_id: int):
        super().__init__()
        self._bot = bot_instance
        self._chat_id = chat_id
        self._sent_files: set[str] = set()  # avoid duplicates on move events

    def _should_send(self, path: str) -> bool:
        p = Path(path)
        if not p.is_file():
            return False
        if str(p) in self._sent_files:
            return False
        # .apk anywhere in project
        if p.suffix.lower() == ".apk":
            return True
        # any file inside output/ directory
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
        """Handle file moves (e.g. download complete → final location)."""
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
            # Small delay to make sure the file is fully written
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
    # Start watchdog
    event_handler = AutoUploadHandler(bot, MY_CHAT_ID)
    # Pass the running event loop to the handler
    loop = asyncio.get_running_loop()
    event_handler._loop = loop

    observer = Observer()
    observer.schedule(event_handler, str(PROJECT_ROOT), recursive=True)
    observer.start()
    log.info("Watchdog watching: %s", PROJECT_ROOT)

    # Start polling
    log.info("Bot starting...")
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
