class BlabClient {
  constructor(baseUrl = "http://localhost:3000") {
    this.baseUrl = baseUrl;
  }

  async createChat(chat) {
    const response = await fetch(`${this.baseUrl}/chat`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(chat),
    });

    if (!response.ok) {
      throw new Error(`Failed to create chat: ${response.statusText}`);
    }

    return response.text();
  }

  async listChats() {
    const response = await fetch(`${this.baseUrl}/chat`);

    if (!response.ok) {
      throw new Error(`Failed to list chats: ${response.statusText}`);
    }

    return response.json();
  }

  async getChat(id) {
    const response = await fetch(`${this.baseUrl}/chat/${id}`);

    if (!response.ok) {
      throw new Error(`Failed to get chat: ${response.statusText}`);
    }

    return response.json();
  }

  async sendMessage(chatId, message) {
    const response = await fetch(`${this.baseUrl}/chat/${chatId}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    });

    if (!response.ok) {
      throw new Error(`Failed to send message: ${response.statusText}`);
    }

    return response.text();
  }

  async deleteChat(id) {
    const response = await fetch(`${this.baseUrl}/chat/${id}`, {
      method: "DELETE",
    });

    if (!response.ok) {
      throw new Error(`Failed to delete chat: ${response.statusText}`);
    }

    return response.text();
  }

  subscribeToChatMessages(chatId, onMessage) {
    const eventSource = new EventSource(
      `${this.baseUrl}/chat/${chatId}/stream`
    );

    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      onMessage(data);
    };

    eventSource.onerror = (error) => {
      console.error("SSE error:", error);
    };

    // Return cleanup function
    return () => eventSource.close();
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = BlabClient;
} else {
  window.BlabClient = BlabClient;
}
