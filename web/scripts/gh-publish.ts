import ghPages from 'gh-pages';

const BASE_PATH = 'public';
const CONFIG: ghPages.PublishOptions = {
    nojekyll: true,
    repo: 'https://github.com/kamaal111/gitreviewit',
};

ghPages.publish(BASE_PATH, CONFIG, error => {
    if (error) {
        console.error('❌', error);
        process.exit(1);
    }

    console.log('🚀 Publish complete');
});
