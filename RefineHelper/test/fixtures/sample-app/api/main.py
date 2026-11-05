from fastapi import FastAPI
from .models import User

app = FastAPI()


@app.get("/items/{item_id}")
def read_item(item_id: int):
    return User(id=item_id)
