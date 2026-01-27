using AppManager.Core;

int main(string[] args) {
    // Initialize translations before anything else
    i18n_init();
    
    var app = new AppManager.Application();
    return app.run(args);
}
