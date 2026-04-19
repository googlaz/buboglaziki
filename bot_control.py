import os
import subprocess
import asyncio
import logging
import aiohttp
import json
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
    await message.answer("👋 Привет! Я Кодя. Готов пилить Buboglaziki!\n\n/code [задача] — изменить код\nПросто текст — поболтать.")

# КОМАНДА ДЛЯ КОДИНГА (Прямой вызов терминала)
@dp.message(Command("code"))
async def handle_code(message: types.Message, command: CommandObject):
    if str(message.from_user.id) != MY_CHAT_ID: return
    
    task = command.args
    if not task:
        await message.answer("❌ Напиши задачу, например: /code сделай время московским")
        return

    await message.answer(f"🛠 Запускаю OpenCode... Задача: {task}")

    try:
        # Запускаем opencode-ai напрямую в системе
        process = await asyncio.create_subprocess_shell(
            f'opencode-ai "{task}" --yes --apply',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        result = stdout.decode(errors='replace').strip() or stderr.decode(errors='replace').strip()
        # Режем вывод до безопасного лимита
        safe = result[:3500] if result else "(пустой вывод)"
        try:
            await message.answer(f"✅ Готово!\n\nОтчет:\n```\n{safe}\n```", parse_mode="Markdown")
        except Exception:
            # Markdown сломался — отправляем без форматирования
            await message.answer(f"✅ Готово!\n\nОтчет:\n{safe}")
    except Exception as e:
        await message.answer(f"❌ Ошибка терминала: {e}")

# ОБЫЧНЫЕ СООБЩЕНИЯ (Общение через нейросеть)
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
    await dp.start_polling(bot, skip_updates=True)

if __name__ == "__main__":
    asyncio.run(main())