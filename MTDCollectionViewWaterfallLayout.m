#import "MTDCollectionViewWaterfallLayout.h"


#define kMTDFooterHeight 50.f


@interface MTDCollectionViewWaterfallLayout()

@property (nonatomic, assign) NSInteger itemCount;
@property (nonatomic, assign) CGFloat interitemSpacing;
@property (nonatomic, strong) NSMutableArray *columnHeights; // height for each column
@property (nonatomic, strong) NSMutableDictionary *itemAttributes; // attributes for each item
@property (nonatomic, strong) UICollectionViewLayoutAttributes *footerAttributes;
@property (nonatomic, strong) NSMutableDictionary *columnIndexes;

@property (nonatomic, strong) NSSet *indexPathsToInsert;
@property (nonatomic, strong) NSSet *indexPathsToDelete;

@end

@implementation MTDCollectionViewWaterfallLayout

#pragma mark - Accessors
- (void)setColumnCount:(NSUInteger)columnCount
{
    if (_columnCount != columnCount) {
        _columnCount = columnCount;
        [self invalidateLayout];
    }
}

- (void)setItemWidth:(CGFloat)itemWidth
{
    if (_itemWidth != itemWidth) {
        _itemWidth = itemWidth;
        [self invalidateLayout];
    }
}

- (void)setSectionInset:(UIEdgeInsets)sectionInset
{
    if (!UIEdgeInsetsEqualToEdgeInsets(_sectionInset, sectionInset)) {
        _sectionInset = sectionInset;
        [self invalidateLayout];
    }
}

#pragma mark - Init
- (void)commonInit
{
    _columnCount = 2;
    _itemWidth = 140.0f;
    _sectionInset = UIEdgeInsetsZero;
    _columnIndexes = [NSMutableDictionary dictionary];
}

- (id)init
{
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

#pragma mark - UICollectionViewLayout

- (CGSize)collectionViewContentSize {
    if (self.itemCount == 0) {
        return CGSizeZero;
    }

    CGSize contentSize = self.collectionView.frame.size;
    NSUInteger columnIndex = [self longestColumnIndex];
    CGFloat height = [self.columnHeights[columnIndex] floatValue];
    contentSize.height = height - self.interitemSpacing + 2*self.sectionInset.bottom + kMTDFooterHeight;

    return contentSize;
}

- (void)invalidateLayout {
    [super invalidateLayout];

    [self.columnIndexes removeAllObjects];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return YES;
}

// we keep track of the indexPaths of the objects that are actually appearing/disappearing
// because initialLayoutAttributesForAppearingItemAtIndexPath: and finalLayoutAttributesForAppearingItemAtIndexPath:
// get called for every item, not only the appearing/disappearing ones
- (void)prepareForCollectionViewUpdates:(NSArray *)updateItems {
    [super prepareForCollectionViewUpdates:updateItems];

    NSUInteger capacity = updateItems.count/3; // rough expectation
    NSMutableSet *insertions = [[NSMutableSet alloc] initWithCapacity:capacity];
    NSMutableSet *deletions = [[NSMutableSet alloc] initWithCapacity:capacity];

    for (MTDCollectionViewUpdateItem *item in updateItems) {
        if (item.updateAction == UICollectionUpdateActionInsert) {
            [insertions addObject:item.indexPathAfterUpdate];
        } else if (item.updateAction == UICollectionUpdateActionDelete) {
            [deletions addObject:item.indexPathBeforeUpdate];
        }
    }

    self.indexPathsToInsert = insertions;
    self.indexPathsToDelete = deletions;
}

- (void)finalizeCollectionViewUpdates {
    [super finalizeCollectionViewUpdates];

    self.indexPathsToInsert = nil;
    self.indexPathsToDelete = nil;
}


- (void)prepareLayout {
    if ([[self collectionView] numberOfSections] > 0) {
        _itemCount = [[self collectionView] numberOfItemsInSection:0];

        NSAssert(_columnCount > 1, @"columnCount for UICollectionViewWaterfallLayout should be greater than 1.");
        CGFloat width = self.collectionView.frame.size.width - _sectionInset.left - _sectionInset.right;
        _interitemSpacing = floorf((width - _columnCount * _itemWidth) / (_columnCount - 1));

        _itemAttributes = [NSMutableDictionary dictionaryWithCapacity:_itemCount];
        _columnHeights = [NSMutableArray arrayWithCapacity:_columnCount];
        for (NSInteger idx = 0; idx < _columnCount; idx++) {
            [_columnHeights addObject:@(_sectionInset.top)];
        }

        // Item will be put into shortest column.on first appear, afterwards they keep their column to not jump around
        for (NSInteger idx = 0; idx < _itemCount; idx++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:idx inSection:0];
            CGFloat itemHeight = [self.delegate collectionView:self.collectionView
                                                        layout:self
                                      heightForItemAtIndexPath:indexPath];

            NSNumber *suggestedColumn = self.columnIndexes[indexPath];

            NSUInteger columnIndex = suggestedColumn != nil ? [suggestedColumn unsignedIntegerValue] : [self shortestColumnIndex];
            CGFloat xOffset = _sectionInset.left + (_itemWidth + _interitemSpacing) * columnIndex;
            CGFloat yOffset = [(_columnHeights[columnIndex]) floatValue];

            self.columnIndexes[indexPath] = @(columnIndex);

            UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
            attributes.frame = CGRectMake(xOffset, yOffset, self.itemWidth, itemHeight);
            attributes.transform3D = CATransform3DIdentity;

            _itemAttributes[indexPath] = attributes;
            _columnHeights[columnIndex] = @(yOffset + itemHeight + _interitemSpacing);

            // footer attributes
            if (idx == _itemCount - 1) {
                self.footerAttributes = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                             atIndexPath:indexPath];
            }
        }
    }
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray *layoutAttributes = [NSMutableArray arrayWithCapacity:self.itemAttributes.count+1];

    [self.itemAttributes enumerateKeysAndObjectsUsingBlock:^(NSIndexPath *indexPath, MTDCollectionViewLayoutAttributes *attributes, BOOL *stop) {
        if (CGRectIntersectsRect(rect, attributes.frame)) {
            [layoutAttributes addObject:attributes];
        }
    }];

    if (CGRectIntersectsRect(rect, self.footerAttributes.frame)) {
        [layoutAttributes addObjectIfNotNil:self.footerAttributes];
    }

    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewLayoutAttributes *attributes = [super layoutAttributesForSupplementaryViewOfKind:kind atIndexPath:indexPath];

    if ([kind isEqualToString:UICollectionElementKindSectionFooter]) {
        CGSize contentSize = self.collectionViewContentSize;

        if (attributes == nil) {
            attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:kind withIndexPath:indexPath];
        }
        
        attributes.frame = CGRectMake(self.sectionInset.left,
                                      contentSize.height - kMTDFooterHeight - self.sectionInset.bottom,
                                      contentSize.width,
                                      kMTDFooterHeight);
    }

    return attributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    return self.itemAttributes[path];
}

//- (UICollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
//    if ([self.indexPathsToInsert containsObject:itemIndexPath]) {
//        return [self layoutAttributesForAppearingOrDisappearingItemAtIndexPath:itemIndexPath];
//    } else {
//        return [self layoutAttributesForItemAtIndexPath:itemIndexPath];
//    }
//}

//- (UICollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
//    if ([self.indexPathsToDelete containsObject:itemIndexPath]) {
//        return [self layoutAttributesForAppearingOrDisappearingItemAtIndexPath:itemIndexPath];
//    } else {
//        return [self layoutAttributesForItemAtIndexPath:itemIndexPath];
//    }
//}

// Private method: we want the same animation when inserting/deleting, just reversed
- (UICollectionViewLayoutAttributes *)layoutAttributesForAppearingOrDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
    UICollectionViewLayoutAttributes *attributes = [self layoutAttributesForItemAtIndexPath:itemIndexPath];

    attributes.transform3D = CATransform3DMakeScale(1/100.f, 1/100.f, 1.f);
    attributes.alpha = 0.f;

    return attributes;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Private
////////////////////////////////////////////////////////////////////////

- (NSUInteger)shortestColumnIndex {
    __block NSUInteger index = 0;
    __block CGFloat shortestHeight = MAXFLOAT;

    [self.columnHeights enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CGFloat height = [obj floatValue];
        if (height < shortestHeight) {
            shortestHeight = height;
            index = idx;
        }
    }];

    return index;
}

- (NSUInteger)longestColumnIndex {
    __block NSUInteger index = 0;
    __block CGFloat longestHeight = 0;

    [self.columnHeights enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CGFloat height = [obj floatValue];
        if (height > longestHeight) {
            longestHeight = height;
            index = idx;
        }
    }];
    
    return index;
}

@end
