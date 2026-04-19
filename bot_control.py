import os
import subprocess
import asyncio
import logging
import aiohttp
import json
import shutil
from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command, CommandObject
from dotenv import load_dotenv

# Загружаем настройки из .env
load_dotenv()
API_TOKEN = os.getenv("BOT_TOKEN")
MY_CHAT_ID = os.getenv("MY_CHAT_ID")
OR_API_KEY = os.getenv("OPENROUTER_API_KEY")

# Настройки модели
MODEL_ID = "openai/gpt-oss-120b" 

logging.basicConfig(level=logging.INFO)

bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# Функция для запроса к OpenRouter (мозг Коди)
async def get_ai_response(user_text):
    url = "https://openrouter.ai/api/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {OR_API_KEY}",
        "Content-Type": "application/json"
    }
    
    # Инструкция для личности Коди
    system_prompt = (
        "Ты — Кодя, остроумный ИИ-помощник крутого юриста и разработчика. "
        "Ты помогаешь развивать проект 'Buboglaziki'. Ты любишь порядок в коде и "
        "иногда шутишь про кавалер-кинг-чарльз-спаниелей. Твоя задача — быть полезным и вежливым."
    )
    
    payload = {
        "model": MODEL_ID,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_text}
        ]
    }

    # Экспоненциальная задержка для обработки ошибок
    for attempt in range(5):
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(url, headers=headers, json=payload) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        return data['choices'][0]['message']['content']
                    elif resp.status == 429: # Too Many Requests
                        await asyncio.sleep(2 ** attempt)
                    else:
                        error_text = await resp.text()
                        return f"Ошибка OpenRouter ({resp.status}): {error_text}"
        except Exception as e:
            await asyncio.sleep(2 ** attempt)
    return "Кодя задумался слишком надолго и не смог ответить..."

# Команда /start
@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    if str(message.from_user.id) != MY_CHAT_ID: return
    await message.answer(
        "👋 Привет! Я Кодя. Готов пилить Buboglaziki!\n\n"
        "/code [задача] — изменить код через OpenCode\n"
        "/cmd [команда] — выполнить shell-команду\n"
        "Просто текст — поболтать."
    )


# Команда /cmd — выполнить любую shell-команду
@dp.message(Command("cmd"))
async def cmd_shell(message: types.Message, command: CommandObject):
    if str(message.from_user.id) != MY_CHAT_ID: return

    cmd = command.args
    if not cmd:
        await message.answer("❌ Напиши команду, например: /cmd git status")
        return

    await message.answer(f"🖥 Выполняю: {cmd[:300]}")

    try:
        process = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=os.getcwd(),
        )
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=120)
        except asyncio.TimeoutError:
            process.kill()
            await message.answer("⏱ Таймаут 2 минуты. Процесс убит.")
            return

        out = stdout.decode(errors='replace').strip()
        err = stderr.decode(errors='replace').strip()
        code = process.returncode

        parts = [f"Exit code: {code}"]
        if out: parts.append(f"STDOUT:\n{out}")
        if err: parts.append(f"STDERR:\n{err}")
        full = "\n\n".join(parts)

        MAX = 3500
        if len(full) <= MAX:
            await message.answer(full or "(пустой вывод)")
        else:
            await message.answer(full[:MAX])
            remaining = full[MAX:]
            n = 2
            while remaining:
                await message.answer(f"[часть {n}]\n{remaining[:MAX]}")
                remaining = remaining[MAX:]
                n += 1
    except Exception as e:
        await message.answer(f"❌ Ошибка: {e}")

# КОМАНДА ДЛЯ КОДИНГА (Прямой вызов терминала)
# Ищем установленный CLI-инструмент для автономного кодинга
def _find_code_cli():
    """Возвращает (путь, имя, список_флагов_перед_задачей) для первого найденного CLI."""
    # Для opencode используем --dangerously-skip-permissions — это единственный способ
    # заставить его реально менять файлы без интерактивных промптов.
    candidates = [
        ("opencode",    "opencode",    ["run", "--dangerously-skip-permissions"]),
        ("opencode-ai", "opencode-ai", ["run", "--dangerously-skip-permissions"]),
        ("claude",      "claude",      ["--yes"]),
    ]
    for name, label, flags in candidates:
        path = shutil.which(name)
        if path:
            return path, label, flags
    return None, None, None


@dp.message(Command("code"))
async def handle_code(message: types.Message, command: CommandObject):
    if str(message.from_user.id) != MY_CHAT_ID: return

    task = command.args
    if not task:
        await message.answer("❌ Напиши задачу, например: /code сделай время московским")
        return

    # 1. Ищем установленный CLI
    cli_path, cli_name, flags = _find_code_cli()
    if not cli_path:
        await message.answer(
            "❌ Не найден CLI для кодинга!\n\n"
            "Установи один из:\n"
            "• npm i -g opencode-ai\n"
            "• npm i -g @anthropic-ai/claude-code"
        )
        return

    await message.answer(
        f"🛠 Запускаю {cli_name} в режиме автономного редактирования...\n"
        f"Задача: {task[:300]}"
    )

    try:
        # Env: разрешаем ВСЕ действия без подтверждения (доп. страховка)
        env = os.environ.copy()
        env["OPENCODE_PERMISSION"] = '{"*":"allow"}'

        # Формируем команду: opencode run --dangerously-skip-permissions "задача"
        # Задача передаётся отдельным аргументом — не через shell, чтобы избежать
        # проблем с экранированием кавычек
        process = await asyncio.create_subprocess_exec(
            cli_path, *flags, task,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=os.getcwd(),
            env=env,
        )

        # Ждём максимум 10 минут (OpenCode может долго работать с большими задачами)
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=600)
        except asyncio.TimeoutError:
            process.kill()
            await message.answer("⏱ Таймаут 10 минут. Процесс убит.")
            return

        out = stdout.decode(errors='replace').strip()
        err = stderr.decode(errors='replace').strip()
        code = process.returncode

        # Собираем отчёт
        parts = [f"Exit code: {code}"]
        if out:
            parts.append(f"--- STDOUT ---\n{out}")
        if err:
            parts.append(f"--- STDERR ---\n{err}")
        full = "\n\n".join(parts)

        status = "✅ Готово!" if code == 0 else f"⚠️ Exit {code}"

        # Отправляем результат частями по 3500 символов
        MAX = 3500
        if len(full) <= MAX:
            await message.answer(f"{status}\n\n{full}")
        else:
            await message.answer(f"{status}\n\n{full[:MAX]}")
            remaining = full[MAX:]
            part_num = 2
            while remaining:
                await message.answer(f"[часть {part_num}]\n{remaining[:MAX]}")
                remaining = remaining[MAX:]
                part_num += 1

        # Подсказка: проверить git-изменения
        if code == 0 and out:
            await message.answer(
                "💡 Проверь изменения:\n"
                "/cmd git status\n"
                "/cmd git diff"
            )

    except Exception as e:
        logging.exception("OpenCode run failed")
        await message.answer(f"❌ Ошибка терминала: {e}")

# ОБЫЧНЫЕ СООБЩЕНИЯ (Общение через нейросеть)
# Ловит только сообщения БЕЗ команд (т.е. не начинаются с /)
@dp.message()
async def chat_handler(message: types.Message):
    if str(message.from_user.id) != MY_CHAT_ID: return
    if not message.text or message.text.startswith('/'): return

    # Показываем статус "печатает", пока ИИ думает
    await bot.send_chat_action(message.chat.id, "typing")

    response = await get_ai_response(message.text)

    # Telegram лимит — 4096 символов. Разбиваем на куски и шлём по очереди.
    MAX_LEN = 4000
    if len(response) <= MAX_LEN:
        try:
            await message.answer(response)
        except Exception as e:
            logging.exception("Send failed")
            await message.answer(f"Ошибка отправки: {e}")
        return

    # Длинный ответ — режем по абзацам/строкам
    chunks = []
    remaining = response
    while len(remaining) > MAX_LEN:
        # Пытаемся разрезать по последнему переносу строки в пределах лимита
        cut = remaining.rfind("\n", 0, MAX_LEN)
        if cut == -1 or cut < MAX_LEN // 2:
            cut = MAX_LEN
        chunks.append(remaining[:cut])
        remaining = remaining[cut:].lstrip()
    if remaining:
        chunks.append(remaining)

    for i, chunk in enumerate(chunks, 1):
        try:
            await message.answer(f"[{i}/{len(chunks)}]\n{chunk}")
        except Exception as e:
            logging.exception("Chunk send failed")
            await message.answer(f"Ошибка отправки части {i}: {e}")

async def main():
    print(f"Кодя запущен (PID: {os.getpid()}) в папке: {os.getcwd()}")

    # Проверка CLI для /code
    cli_path, cli_name, _ = _find_code_cli()
    if cli_path:
        print(f"✅ CLI для /code найден: {cli_name} → {cli_path}")
    else:
        print("⚠️  ВНИМАНИЕ: не найден ни opencode, ни opencode-ai, ни claude.")
        print("   Команда /code не сможет реально менять файлы!")
        print("   Установи: npm i -g opencode-ai  (или @anthropic-ai/claude-code)")

    await dp.start_polling(bot, skip_updates=True)

if __name__ == "__main__":
    asyncio.run(main())