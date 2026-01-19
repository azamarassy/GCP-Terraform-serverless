import functions_framework

@functions_framework.http
def handler(request):
    """Responds to an HTTP request."""
    return "Hello, World!"
